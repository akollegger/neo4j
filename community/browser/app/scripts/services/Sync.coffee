###!
Copyright (c) 2002-2014 "Neo Technology,"
Network Engine for Objects in Lund AB [http://neotechnology.com]

This file is part of Neo4j.

Neo4j is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
###

'use strict';

angular.module('neo4jApp.services')
.service 'SyncService', [
  'localStorageService',
  'NTN'
  'CurrentUser'
  'Utils'
  '$rootScope'
  (localStorageService, NTN, CurrentUser, Utils, $rootScope) ->

    setStorageJSON = (response) ->
      for k, v of response
        continue if /^\$/.test k
        localStorageService.set(k, v) unless k in ['history', 'forEach']

      # Trigger localstorage event for updated_at last, since that is used
      # to set inSync to true
      localStorageService.set('updated_at', 1)
      response

    getStorageJSON = ->
      keys = localStorageService.keys()
      d = {}
      d[k] = localStorageService.get(k) for k in keys
      JSON.stringify(d)

    getStorage = ->
      d = {}
      d.documents = localStorageService.get 'documents'
      d.folders = localStorageService.get 'folders'
      d.stores = localStorageService.get 'stores'
      d.grass = JSON.stringify localStorageService.get('grass')
      d

    $rootScope.$watch 'ntn_data', (ntn_data) ->
      return unless ntn_data
      setStorageJSON ntn_data

    class SyncService
      constructor: ->

        $rootScope.$on 'LocalStorageModule.notification.setitem', (evt, item) =>
          return @setSyncedAt() if item.key is 'updated_at'
          return unless item.key in ['documents', 'folders', 'grass', 'stores']
          return if $rootScope.ntn_data[item.key] == item.newvalue
          $rootScope.ntn_data[item.key] = item.newvalue
          if @authenticated
            @inSync = yes
            @setSyncedAt()
          else
            @inSync = no

        $rootScope.$on 'ntn:authenticated', (evt, authenticated) =>
          @authenticated = authenticated
          @fetchAndUpdate() if authenticated

      fetchAndUpdate: () =>
        promise = @fetch()
        return unless promise
        promise.then( (response) =>
          @setResponse(response)
        )

      fetch: =>
        return unless @authenticated
        NTN.fetch(CurrentUser.getStore())

      push: =>
        return unless @authenticated
        NTN.push(CurrentUser.getStore(), getStorage())
        .then(=> @fetchAndUpdate() )

      setResponse: (response) =>
        @conflict = no
        setStorageJSON(response)

      setSyncedAt: ->
        @inSync = yes
        @lastSyncedAt = new Date()

      authenticated: no
      conflict: no
      inSync: no
      lastSyncedAt: null

    new SyncService()
]
