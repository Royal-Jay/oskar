var InputHelper;

InputHelper = (function() {
  function InputHelper() {}

  InputHelper.isValidStatus = function(status) {
    var numberPattern;
    numberPattern = /^[0-9]$/;
    if (!status.match(numberPattern)) {
      return false;
    }
    return true;
  };

  InputHelper.isAskingForUserStatus = function(input) {
    var response, userPattern;
    userPattern = /^How is <@(\w+)>\s?\??$/i;
    response = input.match(userPattern);
    if (response != null) {
      return response[1];
    }
    return null;
  };

  return InputHelper;

})();

module.exports = InputHelper;
