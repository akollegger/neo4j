###!
Copyright (c) 2002-2015 "Neo Technology,"
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

'use strict'

angular.module('neo4jApp.controllers')
  .config ($provide, $compileProvider, $filterProvider, $controllerProvider) ->
    $controllerProvider.register 'MainCtrl', [
      '$rootScope',
      '$window'
      'Server'
      'Frame'
      'AuthService'
      'AuthDataService'
      'Settings'
      'motdService'
      'UsageDataCollectionService'
      'CurrentUser'
      'ConnectionStatusService'
      ($scope, $window, Server, Frame, AuthService, AuthDataService, Settings, motdService, UDC, CurrentUser, ConnectionStatusService) ->
        $scope.CurrentUser = CurrentUser
        $scope.ConnectionStatusService = ConnectionStatusService

        $scope.kernel = {}
        refresh = ->
          return '' if $scope.unauthorized || $scope.offline
          $scope.labels = Server.labels()
          $scope.relationships = Server.relationships()
          $scope.propertyKeys = Server.propertyKeys()
          $scope.server = Server.info()
          $scope.host = $window.location.host
          fetchJMX()
        $scope.identity = angular.identity

        $scope.motd = motdService
        $scope.auth_service = AuthService

        $scope.neo4j =
          license =
            type: "GPLv3"
            url: "http://www.gnu.org/licenses/gpl.html"
            edition: "Enterprise" # TODO: determine edition via REST

        $scope.$on 'db:changed:labels', refresh

        $scope.today = Date.now()
        $scope.cmdchar = Settings.cmdchar

        #IE < 11 has MSIE in the user agent. IE >= 11 do not.
        $scope.goodBrowser = !/msie/.test(navigator.userAgent.toLowerCase())

        $scope.$watch 'offline', (serverIsOffline) ->
          if (serverIsOffline?)
            if not serverIsOffline
              refresh()
              UDC.ping("connect")
            else
              $scope.errorMessage = motdService.pickRandomlyFromChoiceName('disconnected')

        $scope.$watch 'unauthorized', (isUnauthorized) ->
          refresh()

        $scope.$on 'auth:status_updated', () ->
          $scope.check()

        fetchJMX = ->
          Server.jmx(
            [
              "org.neo4j:instance=kernel#0,name=Configuration"
              "org.neo4j:instance=kernel#0,name=Kernel"
              "org.neo4j:instance=kernel#0,name=Store file sizes"
            ]).success((response) ->
            for r in response
              for a in r.attributes
                $scope.kernel[a.name] = a.value
            UDC.set('store_id',   $scope.kernel['StoreId'])
            UDC.set('neo4j_version', $scope.server.neo4j_version)
          ).error((r)-> $scope.kernel = {})

        fetchServerInfo = ->
          Server.get('/db/manage/server/storeid/').success((response) ->
            $scope.neo4j.store_id = response.storeid
          )
        fetchServerInfo()

        pickFirstFrame = (ls_setup = no) ->
          CurrentUser.autoLogin()
          AuthService.hasValidAuthorization().then(
            ->
              Frame.closeWhere "#{Settings.cmdchar}server connect"
              Frame.create({input:"#{Settings.initCmd}"})
            ,
            (r) ->
              if r.status is 404
                Frame.closeWhere "#{Settings.cmdchar}server connect"
                Frame.create({input:"#{Settings.initCmd}"})
              else
                if !ls_setup and CurrentUser.isAuthenticated()
                  tryAutoConnect()
                  return
                Frame.createOne({input:"#{Settings.cmdchar}server connect"})
          )
        pickFirstFrame()

        tryAutoConnect = ->
          fetchServerInfo().then( ->
            store_creds = CurrentUser.getCurrentStoreCreds $scope.neo4j.store_id
            return Frame.createOne({input:"#{Settings.cmdchar}server connect"}) unless store_creds.creds
            AuthDataService.setEncodedAuthData store_creds.creds
            AuthService.hasValidAuthorization().catch(->
              CurrentUser.removeCurrentStoreCreds $scope.neo4j.store_id
            ).finally(-> pickFirstFrame yes)
          ,->
            Frame.createOne({input:"#{Settings.cmdchar}server connect"})
          )

        $scope.$on 'ntn:data_loaded', (evt, authenticated) ->
          return if ConnectionStatusService.isConnected()
          tryAutoConnect()

        $scope.$watch 'server', (val) ->
          return '' if not val
          $scope.neo4j.version = val.neo4j_version

          if val.neo4j_version then $scope.motd.setCallToActionVersion(val.neo4j_version)
        , true

        refresh()
    ]

  .run([
    '$rootScope'
    'Editor'
    'SyncService'
    ($scope, Editor, SyncService) ->
      $scope.unauthorized = yes
      # everything should be assembled
      # Editor.setContent(":play intro")
      # Editor.execScript(":play intro")
  ])
