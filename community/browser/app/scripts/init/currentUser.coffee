angular.module('neo4jApp')
.run [
  'CurrentUser'
  '$rootScope'
  (CurrentUser, $rootScope) ->
    $rootScope.$on '$locationChangeStart', ->
      CurrentUser.autoLogin()

]
