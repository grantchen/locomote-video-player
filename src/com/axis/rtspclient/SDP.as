package com.axis.rtspclient {

  import flash.utils.ByteArray;
  import flash.external.ExternalInterface;

  public class SDP {
    private var version:int = -1;
    private var origin:Object;
    private var sessionName:String;
    private var timing:Object;
    private var media:Object = new Object;

    public function SDP()
    {
    }

    public function parse(content:ByteArray):Boolean
    {
      var dataString:String = content.toString();

      ExternalInterface.call('console.log', dataString);

      var success:Boolean = true;
      var currentMediaBlock:Object = null;

      /* Could end up with '\r' in the 'line' variable, just keep in mind when matching */
      for each (var line:String in content.toString().split("\n")) {
        line = line.replace(/\r/, '');
        if (0 === line.length) continue;

        switch (line.charAt(0)) {
        case 'v':
          if (-1 !== version) {
            ExternalInterface.call('console.log', 'Version present multiple times in SDP');
            return false;
          }
          success &&= parseVersion(line);
          break;

        case 'o':
          if (null !== origin) {
            ExternalInterface.call('console.log', 'Origin present multiple times in SDP');
            return false;
          }
          success &&= parseOrigin(line);
          break;

        case 's':
          if (null !== sessionName) {
            ExternalInterface.call('console.log', 'Session Name present multiple times in SDP');
            return false;
          }
          success &&= parseSessionName(line);
          break;

        case 't':
          if (null !== timing) {
            ExternalInterface.call('console.log', 'Timing present multiple times in SDP');
            return false;
          }
          success &&= parseTiming(line);
          break;

        case 'm':
          if (null !== currentMediaBlock) {
            /* Complete previous block and store it */
            media[currentMediaBlock.type] = currentMediaBlock;
          }

          /* A wild media block appears */
          currentMediaBlock = new Object();
          currentMediaBlock.rtpmap = new Object();
          parseMediaDescription(line, currentMediaBlock);
          break;

        case 'a':
          parseAttribute(line, currentMediaBlock);
          break;

        default:
          //ExternalInterface.call('console.log', 'Ignored unknown SDP type: ' + line.charAt(0) + '=');
          break;
        }
      }

      media[currentMediaBlock.type] = currentMediaBlock;

      return success;
    }

    private function parseVersion(line:String):Boolean
    {
      var matches:Array = line.match(/^v=(0)$/);
      if (0 === matches.length) {
        ExternalInterface.call('console.log', '\'v=\' (Version) formatted incorrectly: ' + line);
        return false;
      }

      version = 0;

      return true;
    }

    private function parseOrigin(line:String):Boolean
    {
      var matches:Array = line.match(/^o=([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+)$/);
      if (0 === matches.length) {
        ExternalInterface.call('console.log', '\'o=\' (Origin) formatted incorrectly: ' + line);
        return false;
      }

      this.origin = new Object();
      this.origin.username       = matches[1];
      this.origin.sessionid      = matches[2];
      this.origin.sessionversion = matches[3];
      this.origin.nettype        = matches[4];
      this.origin.addresstype    = matches[5];
      this.origin.unicastaddress = matches[6];

      return true;
    }

    private function parseSessionName(line:String):Boolean
    {
      var matches:Array = line.match(/^s=([^ \r\n]+)$/);
      if (0 === matches.length) {
        ExternalInterface.call('console.log', '\'s=\' (Session Name) formatted incorrectly: ' + line);
        return false;
      }

      this.sessionName = matches[1];

      return true;
    }

    private function parseTiming(line:String):Boolean
    {
      var matches:Array = line.match(/^t=([0-9]+) ([0-9]+)$/);
      if (0 === matches.length) {
        ExternalInterface.call('console.log', '\'t=\' (Timing) formatted incorrectly: ' + line);
        return false;
      }

      this.timing = new Object();
      timing.start = matches[1];
      timing.stop  = matches[2];

      return true;
    }

    private function parseMediaDescription(line:String, media:Object):Boolean
    {
      var matches:Array = line.match(/^m=([^ ]+) ([^ ]+) ([^ ]+)[ ]/);
      if (0 === matches.length) {
        ExternalInterface.call('console.log', '\'m=\' (Media) formatted incorrectly: ' + line);
        return false;
      }

      media.type  = matches[1];
      media.port  = matches[2];
      media.proto = matches[3];
      media.fmt   = line.substr(matches[0].length).split(' ').map(function(fmt:*, index:int, array:Array):int {
        return parseInt(fmt);
      });

      return true;
    }

    private function parseAttribute(line:String, media:Object):Boolean
    {
      if (null === media) {
        /* Not in a media block, can't be bothered parsing attributes for session */
        return true;
      }

      if ('video' !== media.type) {
        /* Only support video for now */
        return true;
      }

      var matches:Array; /* Used in some cases of below switch-case */
      var separator:int    = line.indexOf(':');
      var attribute:String = line.substr(0, (-1 === separator) ? 0x7FFFFFFF : separator);

      switch (attribute) {
      case 'a=recvonly':
      case 'a=sendrecv':
      case 'a=sendonly':
      case 'a=inactive':
        media.mode = line.substr('a='.length);
        break;

      case 'a=control':
        media.control = line.substr('a=control:'.length);
        break;

      case 'a=rtpmap':
        matches = line.match(/^a=rtpmap:(\d+) ([^\/]+)\/(\d+)$/);
        if (0 === matches.length) {
          ExternalInterface.call('console.log', 'Could not parse \'rtpmap\' of \'a=\'');
          return false;
        }

        var payload:int = parseInt(matches[1]);
        media.rtpmap[payload] = new Object();
        media.rtpmap[payload].name  = matches[2];
        media.rtpmap[payload].clock = matches[3];
        break;

      case 'a=fmtp':
        matches = line.match(/^a=fmtp:(\d+) (.*)$/);
        if (0 === matches.length) {
          ExternalInterface.call('console.log', 'Could not parse \'fmtp\'  of \'a=\'');
          return false;
        }

        for each (var param:String in matches[2].split('; ')) {
          var idx:int = param.indexOf('=');
          if (param.substr(0, idx) !== 'sprop-parameter-sets') {
            /* Only store sprop-parameter-sets for now */
            continue;
          }

          media.spropParameterSets = param.substr(idx + 1);
        }

        break;
      }

      return true;
    }

    public function getMediaBlock(mediaType:String):Object
    {
      return media[mediaType];
    }
  }
}
