/**
 * Copyright (c) 2002-2015 "Neo Technology,"
 * Network Engine for Objects in Lund AB [http://neotechnology.com]
 *
 * This file is part of Neo4j.
 *
 * Neo4j is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
package org.neo4j.kernel.impl.store.kvstore;

import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

import org.neo4j.helpers.Pair;

class ConcurrentMapState<Key, Meta> extends KeyValueStoreState<Key, Meta>
{
    static class PreState<Key, Meta> extends KeyValueStoreState.Stopped<Key, Meta>
    {
        private final KeyFormat<Key> keys;

        PreState( RotationStrategy<Meta> rotation, KeyFormat<Key> keys )
        {
            super( rotation );
            this.keys = keys;
        }

        @Override
        KeyValueStoreState<Key, Meta> create( File path, KeyValueStoreFile<Meta> store )
        {
            return new ConcurrentMapState<>( rotation, keys, store, path );
        }
    }

    private final RotationStrategy<Meta> rotation;
    private final KeyFormat<Key> keys;
    private final KeyValueStoreFile<Meta> store;
    private final ConcurrentMap<Key, byte[]> changes = new ConcurrentHashMap<>();
    private final File file;

    private ConcurrentMapState( RotationStrategy<Meta> rotation, KeyFormat<Key> keys,
                                KeyValueStoreFile<Meta> store, File file )
    {
        this.rotation = rotation;
        this.keys = keys;
        this.store = store;
        this.file = file;
    }

    @Override
    public String toString()
    {
        return super.toString() + "[" + file + "]";
    }

    @Override
    public File file()
    {
        return file;
    }

    @Override
    KeyValueStoreFile<Meta> openStoreFile( File path ) throws IOException
    {
        return rotation.openStoreFile( path );
    }

    @SuppressWarnings("SynchronizationOnLocalVariableOrMethodParameter")
    public void apply( final AbstractKeyValueStore.Update<Key> update ) throws IOException
    {
        byte[] value = changes.get( update.key );
        if ( value == null )
        {
            final byte[] proposal = new byte[keys.valueSize()];
            synchronized ( proposal )
            {
                value = changes.putIfAbsent( update.key, proposal );
                if ( value == null )
                {
                    BigEndianByteArrayBuffer buffer = new BigEndianByteArrayBuffer( proposal );
                    PreviousValue<Key> lookup = new PreviousValue<>( keys,update.key, proposal );
                    if ( !store.scan( lookup, lookup ) )
                    {
                        buffer.clear();
                    }
                    update.update( buffer );
                    return;
                }
            }
        }
        synchronized ( value )
        {
            update.update( new BigEndianByteArrayBuffer( value ) );
        }
    }

    private static class PreviousValue<Key> extends KeyFormat.Searcher<Key> implements KeyValueVisitor{
        private final byte[] proposal;

        PreviousValue( KeyFormat<Key> keys, Key key, byte[] proposal )
        {
            super( keys, key );
            this.proposal = proposal;
        }

        @Override
        public boolean visit( ReadableBuffer key, ReadableBuffer value )
        {
            value.get( 0, proposal );
            return false;
        }
    }

    @Override
    public KeyValueStoreState<Key, Meta> rotate( Meta metadata ) throws IOException
    {
        try
        {
            Pair<File, KeyValueStoreFile<Meta>> next = rotation.next( file, metadata, keys.filter( dataProvider() ) );
            return new ConcurrentMapState<>( rotation, keys, next.other(), next.first() );
        }
        finally
        {
            store.close();
        }
    }

    public Meta metadata()
    {
        return store.metadata();
    }

    public KeyValueStoreState<Key, Meta> close() throws IOException
    {
        store.close();
        return null;
    }

    public boolean hasChanges()
    {
        return !changes.isEmpty();
    }

    public <Value> Value lookup( Key key, AbstractKeyValueStore.Reader<Value> valueReader ) throws IOException
    {
        byte[] value = changes.get( key );
        if ( value != null )
        {
            return valueReader.parseValue( new BigEndianByteArrayBuffer( value ) );
        }
        ValueFetcher<Key, Value> lookup = new ValueFetcher<>( keys, key, valueReader );
        if ( store.scan( lookup, lookup ) )
        {
            return lookup.value;
        }
        return valueReader.defaultValue();
    }

    private byte[][] sortedUpdates()
    {
        Entry[] buffer = new Entry[changes.size()];
        Iterator<Map.Entry<Key, byte[]>> entries = changes.entrySet().iterator();
        for ( int i = 0; i < buffer.length; i++ )
        {
            Map.Entry<Key, byte[]> next = entries.next(); // we hold the lock, so this should succeed
            byte[] key = new byte[keys.keySize()];
            keys.writeKey( next.getKey(), new BigEndianByteArrayBuffer( key ) );
            buffer[i] = new Entry( key, next.getValue() );
        }
        Arrays.sort( buffer );
        assert !entries.hasNext() : "We hold the lock, so we should see 'size' entries.";
        byte[][] result = new byte[buffer.length * 2][];
        for ( int i = 0; i < buffer.length; i++ )
        {
            result[i * 2] = buffer[i].key;
            result[i * 2 + 1] = buffer[i].value;
        }
        return result;
    }

    /**
     * This method is expected to be called under a lock preventing modification to the state.
     */
    public DataProvider dataProvider() throws IOException
    {
        if ( changes.isEmpty() )
        {
            return store.dataProvider();
        }
        else
        {
            return new KeyValueMerger( store.dataProvider(), new UpdateProvider( sortedUpdates() ),
                                       keys.keySize(), keys.valueSize() );
        }
    }

    public int totalRecordsStored()
    {
        return store.recordCount();
    }

    private static class Entry implements Comparable<Entry>
    {
        final byte[] key, value;

        private Entry( byte[] key, byte[] value )
        {
            this.key = key;
            this.value = value;
        }

        @Override
        public int compareTo( Entry that )
        {
            return BigEndianByteArrayBuffer.compare( this.key, that.key, 0 );
        }
    }

    private static class ValueFetcher<Key, Value> extends KeyFormat.Searcher<Key> implements KeyValueVisitor
    {
        private final AbstractKeyValueStore.Reader<Value> reader;
        Value value;

        ValueFetcher( KeyFormat<Key> keys, Key key, AbstractKeyValueStore.Reader<Value> reader )
        {
            super( keys, key );
            this.reader = reader;
        }

        @Override
        public boolean visit( ReadableBuffer key, ReadableBuffer value )
        {
            this.value = reader.parseValue( value );
            return false;
        }
    }

    private static class UpdateProvider implements DataProvider
    {
        private final byte[][] data;
        private int i;

        UpdateProvider( byte[][] data )
        {
            this.data = data;
        }

        @Override
        public boolean visit( WritableBuffer key, WritableBuffer value ) throws IOException
        {
            if ( i < data.length )
            {
                key.put( 0, data[i] );
                value.put( 0, data[i + 1] );
                i += 2;
                return true;
            }
            return false;
        }

        @Override
        public void close() throws IOException
        {
        }
    }
}
