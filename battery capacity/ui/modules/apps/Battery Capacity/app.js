angular.module('beamng.apps').directive('batteryCapacity', [function () {
  return {
    template: '<span>Battery: {{ display.Capacity }} {{ display.unit }} {{ display.IntervalLabel }} </span></div>',
    replace: true,
    restrict: 'EA',
    link: function (scope, element, attrs) {

      var streamsList = ['electrics']
      var SpeedC = 0
      StreamsManager.add(streamsList)
      scope.display = {
        Capacity: 0,
        unit: '',
        IntervalLabel: ''
      }
    
	  //LoadSettting
      bngApi.engineLua('jsonReadFile(' + bngApi.serializeToLua('/settings/ui_apps/Acceleration -per second-.json') + ')', (settings) => {
      });

      scope.$on('streamsUpdate', function (event, streams) {
        scope.$evalAsync(function () {
          if (!streams.electrics) {
            return
          }

            if (streams.electrics.evfuel){
              SpeedC = streams.electrics.evfuel;
            }
            else{
              SpeedC = 0;
            }

            scope.display.unit = '%'
            scope.display.Capacity = SpeedC.toFixed(2)

        })
        scope.$on('$destroy', function () {
          StreamsManager.remove(streamsList)
        });
      });
    }
  };
}])