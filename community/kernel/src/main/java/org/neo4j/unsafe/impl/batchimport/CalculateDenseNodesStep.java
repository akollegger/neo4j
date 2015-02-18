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
package org.neo4j.unsafe.impl.batchimport;

import org.neo4j.kernel.impl.store.record.RelationshipRecord;
import org.neo4j.unsafe.impl.batchimport.cache.NodeRelationshipLink;
import org.neo4j.unsafe.impl.batchimport.input.InputException;
import org.neo4j.unsafe.impl.batchimport.input.InputRelationship;
import org.neo4j.unsafe.impl.batchimport.staging.ExecutorServiceStep;
import org.neo4j.unsafe.impl.batchimport.staging.StageControl;

import static java.lang.Math.max;

/**
 * Runs through relationship input and counts relationships per node so that dense nodes can be designated.
 */
public class CalculateDenseNodesStep extends ExecutorServiceStep<Batch<InputRelationship,RelationshipRecord>>
{
    private final NodeRelationshipLink nodeRelationshipLink;
    private long highestSeenNodeId;

    public CalculateDenseNodesStep( StageControl control, Configuration config,
            NodeRelationshipLink nodeRelationshipLink )
    {
        super( control, "CALCULATOR", config.workAheadSize(), config.movingAverageSize(), 1 );
        this.nodeRelationshipLink = nodeRelationshipLink;
    }

    @Override
    protected Object process( long ticket, Batch<InputRelationship,RelationshipRecord> batch )
    {
        InputRelationship[] input = batch.input;
        long[] ids = batch.ids;
        for ( int i = 0; i < input.length; i++ )
        {
            InputRelationship rel = input[i];
            long startNode = ids[i*2];
            long endNode = ids[i*2+1];
            ensureNodeFound( "start", rel, startNode );
            ensureNodeFound( "end", rel, endNode );

            try
            {
                nodeRelationshipLink.incrementCount( startNode );
            }
            catch ( ArrayIndexOutOfBoundsException e )
            {
                throw new RuntimeException( "Input relationship " + rel + " refers to missing start node " +
                        rel.startNode(), e );
            }
            if ( !rel.isLoop() )
            {
                try
                {
                    nodeRelationshipLink.incrementCount( endNode );
                }
                catch ( ArrayIndexOutOfBoundsException e )
                {
                    throw new RuntimeException( "Input relationship " + rel + " refers to missing end node " +
                            rel.endNode(), e );
                }
            }

            highestSeenNodeId = max( highestSeenNodeId, max( startNode, endNode ) );
        }
        return null; // end of the line
    }

    private void ensureNodeFound( String nodeDescription, InputRelationship relationship, long actualNodeId )
    {
        if ( actualNodeId == -1 )
        {
            throw new InputException( relationship + " specified " + nodeDescription +
                    " node that hasn't been imported" );
        }
    }
}
