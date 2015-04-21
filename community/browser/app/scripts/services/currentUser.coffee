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
.service 'CurrentUser', [
  'Settings'
  'NTN'
  'localStorageService'
  'jwtHelper'
  '$q'
  '$rootScope'
  (Settings, NTN, localStorageService, jwtHelper, $q, $rootScope) ->
    class CurrentUser
      _user: {}
      store: no

      fetch: ->
        NTN.fetch @store

      getToken: (id) ->
        return no unless id
        localStorageService.get "ntn_#{id}"

      loadUserFromLocalStorage: ->
        @_user = localStorageService.get 'ntn_profile' || {}
        data_token = @getToken 'data_token'
        @store = no
        if @_user and data_token
          @store = NTN.getUserStore @_user.user_id, data_token
          $rootScope.$emit 'ntn:authenticated', 'yes'

      getStore: ->
        @store

      persist: (res) =>
        if res.token then localStorageService.set 'ntn_token', res.token
        if res.data_token then localStorageService.set 'ntn_data_token', res.data_token
        if res.profile then localStorageService.set 'ntn_profile', res.profile
        if res.refreshToken then localStorageService.set 'ntn_refresh_token', res.refreshToken
        @loadUserFromLocalStorage()

      login: ->
        q = $q.defer()

        auto = @autoLogin()
        if auto
          q.resolve()
          return q.promise

        that = @
        NTN.login().then((res) ->
          that.persist res
          q.resolve(res)
        )
        q.promise

      logout: ->
        q = $q.defer()
        localStorageService.remove 'ntn_token'
        localStorageService.remove 'ntn_data_token'
        localStorageService.remove 'ntn_refresh_token'
        localStorageService.remove 'ntn_profile'
        @loadUserFromLocalStorage()
        NTN.logout()
        q.resolve()
        q.promise

      instance: -> angular.copy(@_user)

      isAuthenticated: -> @_user?.user_id

      autoLogin: ->
        return yes if NTN.isAuthenticated()
        token = localStorageService.get('ntn_token')
        return no unless token
        if not jwtHelper.isTokenExpired token
          NTN.authenticate(localStorageService.get('ntn_profile'), token)
          @loadUserFromLocalStorage()
          return yes
        return no

      refreshToken: (refreshToken) ->
        that = @
        return auth.refreshIdToken(refreshToken).then((token)->
            that.persistUser({token: token})
            return token
          )
    new CurrentUser
]
