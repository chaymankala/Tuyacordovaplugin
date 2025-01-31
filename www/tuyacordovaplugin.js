var exec = function exec(method, params) {
    return new Promise(function (resolve, reject) {
      return cordova.exec(resolve, reject, pluginName, method, params);
    });
};

const pluginName = 'Tuyacordovaplugin';

var Home = {
    createHome: function createHome(){
        return exec('home_createHome',[]);
    },
    listHomes: function listHomes(){
        return exec('home_listHomes',[]);
    },
    getCurrentHome : function getCurrentHome(){

    },
    setCurrentHome : function setCurrentHOme(){
        
    },
    listDevices: function listDevices(homeId){
        return exec('home_listDevices',[homeId]);
    }

}

var User = {
    requestRegister : function requestRegister({countryCode, email, password}){
        return exec('user_requestRegister', [countryCode, email, password]);
    },
    register: function register({countryCode, email, password, otp}) {
        return exec('user_register', [countryCode, email, password, otp])
    },
    loginOrRegitserWithUID : function loginOrRegitserWithUID({countryCode, uid, password}){
        return exec('user_loginOrRegitserWithUID',[countryCode, uid,password])
    }
}

var Networking = {
    smartCameraConfiguration: function smartCameraConfiguration(){
        
    }
}

var Utils = {

}

var IPC = {
    startCameraLivePlay : function startCameraLivePlay({devId}, successCallback, errorCallback){
        return cordova.exec(successCallback, errorCallback, pluginName, 'ipc_startCameraLivePlay', [devId]);
    }
}

var Lock = {

}

var Tuya = {
    Home,
    User,
    Networking,
    Utils,
    IPC,
    Lock
}

module.exports = Tuya;