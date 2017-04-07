package
{
	import flash.text.TextField;
	import flash.events.ErrorEvent;
	import flash.events.EventDispatcher;
	import flash.external.ExternalInterface;
	import flash.utils.Dictionary;

	/**
	 * @author Gerard van den Elzen
	 */
	public final class JSCommunicator extends EventDispatcher
	{
		private static const JSMETHOD:String = 'executeMethodFromSWF';
		private var _onResult:Function;
		private var _methods:Dictionary;
		private var _jsMethod:String=JSMETHOD;
		private var _objectID: String
		public var logText : TextField;
		public function JSCommunicator( onResult:Function = null )
		{
			_methods = new Dictionary( true );
			_onResult = onResult;
			if( ExternalInterface.available )
			{
				ExternalInterface.addCallback( "executeMethodInSWF", executeMethodInSWF );
				_objectID=ExternalInterface.objectID;
			}
		}
		public function setCallBack(method:String):void
		{
			if( ExternalInterface.available )
			{
				ExternalInterface.addCallback( method, executeMethodInSWF );
			}
		}
		public function addMethod( name:String, method:Function ):void
		{
			if( _methods[name] == null )
			{
				_methods[name] = method;
			}
		}

		public function removeMethod( name:String ):void
		{
			if( _methods[name] != null )
			{
				delete _methods[name];
			}
		}

		private function executeMethodInSWF( ...param ):String
		{
			var methodName:String = param[0];
			if(logText)
				logText.text+=param.join(':')+"\n";
			var args:Array = param.slice( 1 );
			if( !_methods[methodName] )
			{
				var msg:String=methodName + ':method not found' ;
				dispatchEvent( new ErrorEvent( ErrorEvent.ERROR,true,true, msg) );
				return 'nok msg';
			}
			var func:Function = _methods[methodName];
			try
			{
				if(args)
					return func.apply( this, args );
				else
					return func.apply( this);
			}
			catch( e:Error )
			{
				dispatchEvent( new ErrorEvent( ErrorEvent.ERROR, true,true,e.message+methodName ) );
				return 'nok '+methodName +' failed to execute ' + e.message;
			}
			return 'nok '+methodName +' failed to execute';
		}
		public function callDirect(method:String, param:String=''):void
		{
			if( !ExternalInterface.available )
			{
				dispatchEvent( new ErrorEvent( ErrorEvent.ERROR,true,true,'no externale interface' ) );
			}
			else
			{
				try
				{

					ExternalInterface.call( method, param );

				}
				catch( e:Error )
				{
					dispatchEvent( new ErrorEvent( ErrorEvent.ERROR, false, false, e.message, e.errorID ) );
				}
			}
		}
		public function call( method:String, param:String='' ):void
		{
			if( !ExternalInterface.available )
			{
				dispatchEvent( new ErrorEvent( ErrorEvent.ERROR,true,true,'no externale interface' ) );
			}
			else
			{
				try
				{

					var result:String = ExternalInterface.call( _jsMethod,_objectID, method, param );
					if( _onResult!=undefined )
					{
						_onResult( result );
					}

				}
				catch( e:Error )
				{
					dispatchEvent( new ErrorEvent( ErrorEvent.ERROR, false, false, e.message, e.errorID ) );
				}
			}
		}

		public function set jsMethod(jsMethod : String) : void
		{
			_jsMethod = jsMethod;
		}
	}
}
