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
  .controller 'FireController', [
    '$scope'
    ($scope) ->

      $scope.firename = 'ABK'
      $scope.firechat = 'Liar!'

      $scope.messages = []

      relatedFire = new Firebase("https://relate.firebaseio.com");
      relatedFire.authWithOAuthPopup("github",
        (error, authData) =>
          if (error)
            console.log("Login Failed!", error)
          else
            console.log("Authenticated successfully with payload:", authData)
            $scope.firename = authData.github.displayName
        ,
        {
          scope: "user,gist"
        }
      )

      chatStream = relatedFire.child("stream")

      chatStream.on('child_added', (snapshot) ->
        message = snapshot.val()
        $scope.messages.push(message)
      )


      $scope.send = () ->
        # demoFire.set('User ' + $scope.firename + ' says ' + $scope.firechat);
        chatStream.push({name: $scope.firename, text: $scope.firechat});


  ]
