package {
	import flash.net.SharedObject;
	import flash.events.TimerEvent;
	import flash.utils.Timer;
	import flash.text.TextField;
	import flash.media.SoundTransform;
	import flash.events.ActivityEvent;
	import flash.external.ExternalInterface;
	import flash.display.Sprite;
	import flash.events.AsyncErrorEvent;
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.events.NetStatusEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.StatusEvent;
	import flash.media.Microphone;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.net.ObjectEncoding;
	import flash.system.Security;
	import flash.system.SecurityPanel;

	[SWF(width="215", height="138", backgroundColor="0x2A2A2A", frameRate="31")]

	public class Intercom extends Sprite {
		private static const PUBLISH : String = "publish";
		private static const PLAY : String = "play";
		private static const WAIT_DELAY : Number = 5000;

		private var _jsCommunicator : JSCommunicator;
		private var _ready : Boolean;
		private var _netConnectionPublish : NetConnection;
		private var _netConnectionPlay : NetConnection;
		private var _microphone : Microphone;
		private var _streamNamePublish : String;
		private var _streamNamePlay : String;
		private var _publishStream : NetStream;
		private var _playStream : NetStream;
		private var _debugMode : Boolean;
		private var _rtmpPublishURL : String;
		private var _rtmpPlayURL : String;
		private var _readyFunction : String;
		private var _numChildren : int;
		private var _playbackVolume : Number = 1;
		private var  _playbackMuted : Boolean = true;
		private var _logText : TextField;
		private var _isPublishing : Boolean = false;
		private var _timeOutTimer : Timer;

		public function Intercom()
		{
			var sprite : Sprite = new Sprite();
			with(sprite.graphics) {
				beginFill(0xDDDDDD, 0);
				drawRect(0, 10, 215, 138);
			}
			sprite.x = 4;
			sprite.y = 4;
			addChild(sprite);
			makeCloseButton();
			_timeOutTimer = new Timer(WAIT_DELAY, 1);
			_timeOutTimer.addEventListener(TimerEvent.TIMER_COMPLETE, onTimeOut);
			addEventListener(Event.ADDED_TO_STAGE, initUI);
		}



		private function makeCloseButton() : void
		{
			var sprite : Sprite = new Sprite();
			with(sprite.graphics) {
				beginFill(0xff0000, 1);
				drawCircle(215 / 2, 138 / 2, 138 / 4);
				endFill();
				beginFill(0xffffff, 1);
				drawRect(215 / 2 - 30, 138 / 2 - 5, 60, 10);
			}
			addChild(sprite);
			sprite.buttonMode = true;
			sprite.useHandCursor = true;
			sprite.addEventListener(MouseEvent.MOUSE_DOWN, onClose);
		}

		private function onClose(event : MouseEvent) : void
		{
			_jsCommunicator.call(AS2JS.ON_SETTINGS_CLOSED);
		}

		private function initUI(event : Event) : void
		{
			addEventListener(StatusEvent.STATUS, onMikeStatus);
			_numChildren = stage.numChildren;
			initJStoAS();
			checkParameter();
			tellReady();
			getAccess();
			_microphone = Microphone.getMicrophone();
			setUpMicrophone();
		}

		private function getAccess() : void
		{
			try{
				var so:SharedObject=SharedObject.getLocal('Selector_Intercom',"/");
				if(!so.data.allowed)
				{
					Security.showSettings(SecurityPanel.PRIVACY);
					so.data.allowed=true;
					so.flush();
				}
			}
			catch(e:Error) {
				Security.showSettings(SecurityPanel.PRIVACY);
			}
		}


		private function onMicrophoneStatus(event : StatusEvent) : void
		{
			if(!_microphone ) {
				_jsCommunicator.call(AS2JS.ON_AUDIO_SELECTED, 'none');
			} else {
				if(_microphone.muted) {
					_jsCommunicator.call(AS2JS.ON_AUDIO_ACCESS, 'false');
				} else {
					_jsCommunicator.call(AS2JS.ON_AUDIO_SELECTED, _microphone.name);
				}
			}
		}

		private function tellReady() : void
		{
			_jsCommunicator.call(AS2JS.ON_SHOW_MESSAGE, 'FlashVars ReadyFuntion:' + _readyFunction);
			if(_readyFunction) {
				_jsCommunicator.callDirect(_readyFunction, ExternalInterface.objectID);
			} else {
				_jsCommunicator.call(AS2JS.ON_READY, ExternalInterface.objectID);
			}
		}

		/*
		 * These methods can be called form JS
		 */
		private function initJStoAS() : void
		{
			_jsCommunicator = new JSCommunicator(onJSResult);
			_jsCommunicator.addEventListener(ErrorEvent.ERROR, onJSError);
			_jsCommunicator.addMethod(JS2AS.CONNECT_RTMP_PLAY, connectRTMPPlay);
			_jsCommunicator.addMethod(JS2AS.CONNECT_RTMP_PUBLISH, connectRTMPPublish);
			_jsCommunicator.addMethod(JS2AS.DISCONNECT_RTMP_PLAY, disconnectRTMPPlay);
			_jsCommunicator.addMethod(JS2AS.DISCONNECT_RTMP_PUBLISH, disconnectRTMPPublish);
			_jsCommunicator.addMethod(JS2AS.LIST_AUDIO_INPUTS, listAudioInputs);
			_jsCommunicator.addMethod(JS2AS.GET_CURRENT_AUDIO_INPUT, getCurrentAudioInput);
			_jsCommunicator.addMethod(JS2AS.ASK_AUDIO_ACCESS, hasAudioAccess);
			_jsCommunicator.addMethod(JS2AS.SHOW_AUDIO_ACCESS, showAudioAccess);
			_jsCommunicator.addMethod(JS2AS.SET_AUDIO_INPUT, setAudioInput);
			_jsCommunicator.addMethod(JS2AS.START_TALKING, startTalking);
			_jsCommunicator.addMethod(JS2AS.STOP_TALKING, stopTalking);
			_jsCommunicator.addMethod(JS2AS.START_PLAYING, startPlaying);
			_jsCommunicator.addMethod(JS2AS.STOP_PLAYING, stopPlaying);
			_jsCommunicator.addMethod(JS2AS.JS_READY, jsready);
			_jsCommunicator.addMethod(JS2AS.SET_GAIN, setGain);
			_jsCommunicator.addMethod(JS2AS.SET_VOLUME, setVolume);
			_jsCommunicator.addMethod(JS2AS.MUTE_PLAYBACK, mutePlayBack);
		}


		private function checkParameter() : void
		{
			if (loaderInfo.parameters.debug != undefined && loaderInfo.parameters.debug == "true") {
				_debugMode = true;
			}

			if(loaderInfo.parameters.readyFunction != undefined) {
				_readyFunction = cleanEIString(loaderInfo.parameters.readyFunction);
			}
			if(loaderInfo.parameters.functionToCall != undefined) {

				_jsCommunicator.jsMethod = loaderInfo.parameters.functionToCall;
			}
			if(_debugMode) {
				setDebugger();
				debug('Debugging')
			}
		}

		private function debug(msg : String) : void
		{
			if(_logText)
				_logText.text += msg + "\n";
		}

		private function setDebugger() : void
		{
			_logText = new TextField();
			addChild(_logText);
			_logText.width = width;
			_logText.height = height;
			_logText.multiline = true;
			_jsCommunicator.logText = _logText;
		}

		private function cleanEIString(pString : String) : String
		{
			return pString.replace(/[^A-Za-z0-9_.]/gi, "");
		}

		private function onJSError( event : ErrorEvent ) : void
		{
			_jsCommunicator.call(AS2JS.ON_SHOW_MESSAGE, 'Error ' + event.text);
		}

		private function stopTalking(param : String = null) : String
		{
			if(_publishStream) {
				_publishStream.close();
				_jsCommunicator.call(AS2JS.ON_PUBLISH_STOPPED, _streamNamePublish);
				_publishStream.removeEventListener(NetStatusEvent.NET_STATUS, onNetStreamStatus);
				_publishStream = null;
			}
			_isPublishing = false;
			return 'ok';
		}

		private function setAudioInput(param : String) : String
		{
			var micNames : Array = Microphone.names;
			var index : int = micNames.indexOf(param);
			if(index == -1) {
				_jsCommunicator.call(AS2JS.ON_SHOW_MESSAGE, 'Parameter audioinput ' + param);
				return 'nok invalid inputname';
			}
			_microphone = Microphone.getMicrophone(index);
			setUpMicrophone();
			if(!_microphone) {
				_jsCommunicator.call(AS2JS.ON_AUDIO_SELECTED, 'none');
				return 'nok no audio selected';
			}
			if(_microphone && _microphone.muted ) {
				_jsCommunicator.call(AS2JS.ON_AUDIO_ACCESS, 'false');
				return 'nok no audio access';
			}

			_jsCommunicator.call(AS2JS.ON_AUDIO_SELECTED, _microphone.name);
			return 'ok';
		}

		private function setUpMicrophone() : void
		{
			_microphone.addEventListener(StatusEvent.STATUS, onMicrophoneStatus);
			_microphone.setLoopBack(true);
			_microphone.soundTransform = new SoundTransform(0);
			_microphone.addEventListener(ActivityEvent.ACTIVITY, onMicActivity);
		}

		private function setGain(param : String) : String
		{
			if(!_microphone) {
				return 'nok no audio selected';
			}
			if(_microphone && _microphone.muted ) {
				return 'nok no audio access';
			}
			_microphone.gain = Number(param);
			return 'ok ' + _microphone.gain;
		}

		private function setVolume(param : String) : String
		{
			if(!_playStream) {
				return 'nok no playStream';
			}
			_playbackVolume = Number(param) / 100;
			checkMuting();
			return 'ok ' + param;
		}

		private function mutePlayBack(param : String) : String
		{
			(param == "true " ) ? _playbackMuted = true : _playbackMuted = false;
			checkMuting();
			return 'ok';
		}

		private function checkMuting() : void
		{
			if(!_playStream) {
				return;
			}
			(_playbackMuted && _isPublishing) ? _playStream.soundTransform = new SoundTransform(0) : _playStream.soundTransform = new SoundTransform(_playbackVolume);
		}

		private function onMicActivity(event : ActivityEvent) : void
		{
			_jsCommunicator.call(AS2JS.ON_AUDIO_ACTIVITY, String(_microphone.activityLevel));
		}

		private function startTalking(stream : String) : String
		{
			if(!_netConnectionPublish || !_netConnectionPublish.connected ) {
				return 'nok no publish connection';
			}
			if( !_microphone  ) {
				return 'nok no audio input';
			}
			if( _microphone.muted  ) {
				return 'nok no audio access';
			}
			if((stream == null || stream == "") ) {
				if( _streamNamePublish == null) {
					return 'nok no outputStream defined';
				}
			} else {
				_streamNamePublish = stream;
			}
			createPublishStream();
			return 'ok';
		}

		private function createPublishStream() : void
		{
			_publishStream = new NetStream(_netConnectionPublish);
			_publishStream.addEventListener(NetStatusEvent.NET_STATUS, onNetStreamStatus);
			_publishStream.attachAudio(_microphone);
			_publishStream.publish(_streamNamePublish);
			_isPublishing = true;
			checkMuting();
		}

		private function startPlaying(stream : String) : String
		{
			if(!_netConnectionPlay || !_netConnectionPlay.connected) {
				return 'nok no valid playconnection';
			}
			if(stream != null && stream != "") {
				_streamNamePlay = stream;
			}
			if(_streamNamePlay != null) {
				createPlayStream();
				return 'ok';
			}
			return 'nok no valid playstream name';
		}

		private function stopPlaying(stream : String) : String
		{
			if(_playStream) {
				_playStream.close();
				_playStream = null;
				return 'ok';
			}
			return 'nok no valid playstream';
		}

		private function jsready(param : String = null) : String
		{
			if(!_ready) {
				_ready = true;
				_jsCommunicator.call(AS2JS.ON_READY, ExternalInterface.objectID);
			}
			return ExternalInterface.objectID;
		}

		private function connectRTMPPlay(rtmp_stream : String) : String
		{
			var tmpArray : Array = rtmp_stream.split('|');
			if(tmpArray.length == 2) {
				_streamNamePlay = tmpArray[1];
				var rtmp : String = tmpArray[0];
			} else {
				rtmp = tmpArray[0];
			}
			if(hasPublishConnection) {
				_jsCommunicator.call(AS2JS.ON_RTMP_CONNECTED, PLAY);
			} else {
				initConnectionPlay(rtmp);
			}
			return 'ok' ;
		}

		private function connectRTMPPublish(rtmp_stream : String) : String
		{
			var tmpArray : Array = rtmp_stream.split('|');
			if(tmpArray.length == 2) {
				_streamNamePublish = tmpArray[1];
				var rtmp : String = tmpArray[0];
			} else {
				var rtmp : String = tmpArray[0];
			}
			if(hasPublishConnection) {
				_jsCommunicator.call(AS2JS.ON_RTMP_CONNECTED);
			} else {
				initConnectionPublish(rtmp);
			}
			return 'ok' ;
		}

		private function disconnectRTMPPublish(param : String = null) : String
		{
			if(hasPublishConnection) {
				_netConnectionPublish.close();
			} else {
				_jsCommunicator.call(AS2JS.ON_RTMP_NOT_CONNECTED);
			}
			return 'ok';
		}

		private function disconnectRTMPPlay(param : String = null) : String
		{
			if(hasPlayConnection) {
				_netConnectionPlay.close();
			} else {
				_jsCommunicator.call(AS2JS.ON_RTMP_NOT_CONNECTED);
			}
			return 'ok';
		}

		private function listAudioInputs(param : String = null) : String
		{
			return Microphone.names.join('|');
		}

		private function hasAudioAccess(param : String = null) : Boolean
		{
			return (!_microphone || _microphone.muted) ? false : true;
		}

		private function getCurrentAudioInput(param : String = null) : String
		{
			return (!_microphone || _microphone.muted) ? 'none' : _microphone.name;;
		}

		private function showAudioAccess(param : String = null) : String
		{
			Security.showSettings(SecurityPanel.PRIVACY);
			addEventListener(MouseEvent.MOUSE_OVER, onSettingsClosed);
			addEventListener(MouseEvent.MOUSE_MOVE, onSettingsClosed);
			return 'ok';
		}

		private function onSettingsClosed(event : Event = null) : void
		{
			removeEventListener(MouseEvent.MOUSE_OVER, onSettingsClosed);
			removeEventListener(MouseEvent.MOUSE_MOVE, onSettingsClosed);
			_microphone = Microphone.getMicrophone();
			_microphone.setLoopBack(false);
			if(_microphone && !_microphone.muted) {
				_jsCommunicator.call(AS2JS.ON_AUDIO_ACCESS, "true");
			} else {
				_jsCommunicator.call(AS2JS.ON_AUDIO_ACCESS, "false");
			}
			_jsCommunicator.call(AS2JS.ON_SETTINGS_CLOSED);
		}

		private function onMikeStatus(event : StatusEvent) : void
		{
			switch(event.code) {
				case "Microphone.Muted":
					_jsCommunicator.call(AS2JS.ON_AUDIO_ACCESS, "false");
					break;
				case "Microphone.UnMuted":
					_jsCommunicator.call(AS2JS.ON_AUDIO_ACCESS, "true");
					_microphone = Microphone.getMicrophone();
					_microphone.setLoopBack(false);
					break;
			}
		}

		private function onJSResult(param : String) : void
		{
		}

		/*
		 *
		 */
		private function get hasPublishConnection() : Boolean {
			if(!_netConnectionPublish)
		 		return false;
			return _netConnectionPublish.connected;
		}

		private function get hasPlayConnection() : Boolean {
			if(!_netConnectionPlay)
		 		return false;
			return _netConnectionPlay.connected;
		}

		private function initConnectionPublish(param : String) : void
		{
			if(!_netConnectionPublish) {
				_netConnectionPublish = new NetConnection();
				_netConnectionPublish.objectEncoding = ObjectEncoding.AMF3;
				_netConnectionPublish.addEventListener(NetStatusEvent.NET_STATUS, onNetConnectionStatus);
				_netConnectionPublish.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
				_netConnectionPublish.addEventListener(AsyncErrorEvent.ASYNC_ERROR, onAsyncError);
			}
			_rtmpPublishURL = param;
			_netConnectionPublish.connect(param);
			_timeOutTimer.reset();
			_timeOutTimer.start()
		}

		private function initConnectionPlay(param : String) : void
		{
			if(!_netConnectionPlay) {
				_netConnectionPlay = new NetConnection();
				_netConnectionPlay.objectEncoding = ObjectEncoding.AMF3;
				_netConnectionPlay.addEventListener(NetStatusEvent.NET_STATUS, onNetConnectionStatus);
				_netConnectionPlay.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
				_netConnectionPlay.addEventListener(AsyncErrorEvent.ASYNC_ERROR, onAsyncError);
			}
			_rtmpPlayURL = param;
			_netConnectionPlay.connect(param);
			_timeOutTimer.reset();
			_timeOutTimer.start()
		}

		private  function  onSecurityError(e : SecurityErrorEvent) : void
		{
			//Logger.writeLog("ConnectionManger SecurityErrorEvent ");
		}

		private function onAsyncError(event : AsyncErrorEvent) : void
		{
			//Logger.writeLog("ConnectionManger AsyncErrorEvent ", event.error);
		}

		private  function onNetConnectionStatus(e : NetStatusEvent) : void
		{
			_timeOutTimer.reset();
			_timeOutTimer.stop();
			var netConnection : NetConnection = e.currentTarget as NetConnection;
			var type : String;
			(netConnection.uri == _rtmpPlayURL) ? type = PLAY : type = PUBLISH;
			var infoCode : String = e.info['code'];
			switch(infoCode) {
				case "NetConnection.Connect.Success":
					if( _streamNamePlay != null && type == PLAY) {
						createPlayStream();
					}
					_jsCommunicator.call(AS2JS.ON_RTMP_CONNECTED, type);
					break;
				case "NetConnection.Connect.Failed":
				case "NetConnection.Connect.Rejected":
					_jsCommunicator.call(AS2JS.ON_RTMP_FAILED, type + ":" + infoCode + ":" + netConnection.uri);
					break;
				case "NetConnection.Connect.Closed":
					_jsCommunicator.call(AS2JS.ON_RTMP_NOT_CONNECTED, type + ":" + netConnection.uri);
					break;

				default:
					_jsCommunicator.call(AS2JS.ON_SHOW_MESSAGE, e.info['code']);
			}
		}

		private function onTimeOut(event : TimerEvent) : void
		{
			_jsCommunicator.call(AS2JS.ON_RTMP_NOT_CONNECTED, 'timeout');
		}

		private  function onNetStreamStatus(e : NetStatusEvent) : void
		{
			//var netStream : NetStream = e.currentTarget as NetStream;
			var infoCode : String = e.info['code'];
			switch(infoCode) {
				case "NetStream.Play.PublishNotify":
				case 'NetStream.Publish.Start':
					_jsCommunicator.call(AS2JS.ON_PUBLISH_STARTED, _streamNamePublish);
					break;
				case 'NetStream.Play.UnpublishNotify':
				case 'NetStream.Unpublish.Success':
					_jsCommunicator.call(AS2JS.ON_PUBLISH_STOPPED, _streamNamePublish);
					break;
				case 'NetStream.Publish.BadName':
					_jsCommunicator.call(AS2JS.ON_PUBLISH_FAILED, _streamNamePublish);
					break;
				case "NetStream.Play.Failed":
					_jsCommunicator.call(AS2JS.ON_PLAY_FAILED, _streamNamePlay + ":" + infoCode);
					break;
				case "NetStream.Play.StreamNotFound":
					_jsCommunicator.call(AS2JS.ON_PLAY_FAILED, _streamNamePlay + ":" + infoCode);
					break;
				case "NetStream.Play.Start":
					_jsCommunicator.call(AS2JS.ON_PLAY_STARTED, _streamNamePlay);
					break;
				default:
					_jsCommunicator.call(AS2JS.ON_SHOW_MESSAGE, e.info['code']);
			}
		}

		private function createPlayStream() : void
		{
			_playStream = new NetStream(_netConnectionPlay);
			_playStream.addEventListener(NetStatusEvent.NET_STATUS, onNetStreamStatus);
			_playStream.play(_streamNamePlay);
			checkMuting();
		}
	}
}
