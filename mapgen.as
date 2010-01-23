// Generate a fantasy-world map
// Author: amitp@cs.stanford.edu
// License: MIT

// TODO:
// 1. break up generation into stages (low res, then high res, then wind)
// 2. link stages to onEnterFrame so that the system isn't unresponsive
// 3. make lighting size-independent
// 4. make blurring optional

package {
  import flash.geom.*;
  import flash.display.*;
  import flash.filters.*;
  import flash.text.*;
  import flash.events.*;
  import flash.utils.*;
  import flash.net.*;

  public class mapgen extends Sprite {
    public static var SEED:int = 72689;
    // 83980, 59695, 94400, 92697, 30628, 9146, 23896, 60489, 57078, 89680, 10377, 42612, 29732
    public static var OCEAN_ALTITUDE:int = 1;
    public static var SIZE:int = 512;
    public static var BIGSIZE:int = 2048;
    public static var DETAILSIZE:int = 128;

    public var seed_text:TextField = new TextField();
    public var seed_button:TextField = new TextField();
    public var save_altitude_button:TextField = new TextField();
    public var save_moisture_button:TextField = new TextField();
    public var location_text:TextField = new TextField();
    public var moisture_iterations:TextField = new TextField();
    public var generate_button:TextField = new TextField();

    public var map:Map = new Map(SIZE, SEED);
    public var detailMap:BitmapData = new BitmapData(DETAILSIZE, DETAILSIZE);
    public var colorMap:BitmapData;
    public var lightingMap:BitmapData;
    public var moistureBitmap:BitmapData;
    public var altitudeBitmap:BitmapData;
    
    public function mapgen() {
      colorMap = new BitmapData(SIZE, SIZE);
      lightingMap = new BitmapData(SIZE, SIZE);
      moistureBitmap = new BitmapData(SIZE, SIZE);
      altitudeBitmap = new BitmapData(SIZE, SIZE);
      
      stage.scaleMode = "noScale";
      stage.align = "TL";
      stage.frameRate = 60;
      
      addChild(new Debug(this));
      
      graphics.beginFill(0xccccdd);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();

      function createLabel(text:String, x:int, y:int):TextField {
        var t:TextField = new TextField();
        t.text = text;
        t.width = 0;
        t.x = x;
        t.y = y;
        t.autoSize = TextFieldAutoSize.RIGHT;
        t.selectable = false;
        return t;
      }
      
      function changeIntoEditable(field:TextField, text:String):void {
        field.text = text;
        field.background = true;
        field.autoSize = TextFieldAutoSize.LEFT;
        field.type = TextFieldType.INPUT;
      }
      
      function changeIntoButton(button:TextField, text:String):void {
        button.text = text;
        button.background = true;
        button.selectable = false;
        button.autoSize = TextFieldAutoSize.LEFT;
        button.filters = [new BevelFilter(1)];
      }

      addChild(createLabel("Generating maps of size "
                           + SIZE + "x" + SIZE, 255, 2));
      addChild(createLabel("Amit J Patel -- "
                          + "http://simblob.blogspot.com/", 260+512, 515));
      
      changeIntoEditable(seed_text, "" + map.SEED);
      seed_text.restrict = "0-9";
      seed_text.x = 50;
      seed_text.y = 40;
      addChild(seed_text);
      addChild(createLabel("Seed:", 50, 40));
               
      changeIntoEditable(moisture_iterations, "4");
      moisture_iterations.restrict = "0-9";
      moisture_iterations.x = 150;
      moisture_iterations.y = 40;
      addChild(moisture_iterations);
      addChild(createLabel("Wind iter:", 150, 40));

      changeIntoButton(generate_button, " Update Map ");
      generate_button.x = 180;
      generate_button.y = 40;
      generate_button.addEventListener(MouseEvent.MOUSE_UP,
                                       function (e:Event):void {
                                         map.SEED = int(seed_text.text);
                                         newMap();
                                       });
      addChild(generate_button);

      changeIntoButton(seed_button, " Randomize ");
      seed_button.x = 20;
      seed_button.y = 70;
      seed_button.addEventListener(MouseEvent.MOUSE_UP,
                                   function (e:Event):void {
                                     map.SEED = int(100000*Math.random());
                                     seed_text.text = "" + map.SEED;
                                     moisture_iterations.text = "" + (1 + int(9*Math.random()));
                                     newMap();
                                   });
      addChild(seed_button);

      changeIntoButton(save_moisture_button, " Export ");
      save_moisture_button.x = 60;
      save_moisture_button.y = 380;
      save_moisture_button.addEventListener(MouseEvent.MOUSE_UP,
                                   function (e:Event):void {
                                     saveMoistureMap();
                                   });
      addChild(save_moisture_button);
      addChild(createLabel("Moisture:", 60, 380));

      b = new Bitmap(moistureBitmap);
      b.x = 0;
      b.y = 400;
      b.scaleX = 128.0/SIZE;
      b.scaleY = b.scaleX;
      addChild(b);

      changeIntoButton(save_altitude_button, " Export ");
      save_altitude_button.x = 190;
      save_altitude_button.y = 380;
      save_altitude_button.addEventListener(MouseEvent.MOUSE_UP,
                                   function (e:Event):void {
                                     saveAltitudeMap();
                                   });
      addChild(save_altitude_button);
      addChild(createLabel("Altitude:", 190, 380));

      b = new Bitmap(altitudeBitmap);
      b.x = 130;
      b.y = 400;
      b.scaleX = 128.0/SIZE;
      b.scaleY = b.scaleX;
      addChild(b);

      // NOTE: Bitmap and Shape objects do not support mouse events,
      // so I'm wrapping the bitmap inside a sprite.
      var s:Sprite = new Sprite();
      s.x = 2;
      s.y = 120;
      s.scaleX = s.scaleY = 256.0/SIZE;
      s.addEventListener(MouseEvent.MOUSE_DOWN,
                         function (e:MouseEvent):void {
                           s.addEventListener(MouseEvent.MOUSE_MOVE, onMapClick);
                           onMapClick(e);
                         });
      stage.addEventListener(MouseEvent.MOUSE_UP,
                             function (e:MouseEvent):void {
                               s.removeEventListener(MouseEvent.MOUSE_MOVE, onMapClick);
                             });
        
      s.addChild(new Bitmap(colorMap));
      s.addChild(new Bitmap(lightingMap)).blendMode = BlendMode.HARDLIGHT;
      addChild(s);

      location_text.x = 20;
      location_text.y = 100;
      location_text.autoSize = TextFieldAutoSize.LEFT;
      addChild(location_text);

      var b:Bitmap = new Bitmap(detailMap);
      b.x = 260;
      b.y = 0;
      b.scaleX = 512.0 / DETAILSIZE;
      b.scaleY = 512.0 / DETAILSIZE;
      addChild(b);
      
      newMap();
    }

    public function saveAltitudeMap():void {
      // Save the altitude minimap (not the big map, where we don't have altitude)
      new FileReference().save(flattenArray(map.altitude, SIZE));
    }

    public function saveMoistureMap():void {
      // Save the moisture minimap (not the big map)
      new FileReference().save(flattenArray(map.moisture, SIZE));
    }

    public function flattenArray(A:Vector.<Vector.<int>>, size:int):ByteArray {
      var B:ByteArray = new ByteArray();
      for (var x:int = 0; x < size; x++) {
        for (var y:int = 0; y < size; y++) {
          B.writeByte(A[x][y]);
        }
      }
      return B;
    }
    
    public function onMapClick(event:MouseEvent):void {
      location_text.text = "" + event.localX + ", " + event.localY;
      generateDetailMap(event.localX, event.localY);
    }

    // We want to incrementally generate the map using onEnterFrame,
    // so the remaining commands needed to generate the map are stored here.
    // _commands is a an array of ["explanatory text", function].
    private var _commands:Array = [];
    public function newMap():void {
      // Invariant: if _commands is empty, there is no event listener
      if (_commands.length == 0) {
        addEventListener(Event.ENTER_FRAME, onEnterFrame);
      }

      _commands = [];
      _commands.push(["Generating coarse map",
                      function():void {
                         map = new Map(128, SEED);
                         map.generate();
                         channelsToLighting();
                       }]);
      _commands.push(["Generating detail map",
                      function():void {
                         map = new Map(SIZE, SEED);
                         map.generate();
                         channelsToLighting();
                         arrayToBitmap(map.altitude, altitudeBitmap);
                       }]);
      for (var i:int = 0; i < int(moisture_iterations.text); i++) {
        _commands.push(["Wind iteration " + (1+i),
                        function():void {
                           map.spreadMoisture();
                           // map.blurMoisture();
                         }]);
      }
    }

    public function onEnterFrame(event:Event):void {
      if (_commands.length > 0) {
        var command:Array = _commands.shift();
        location_text.text = command[0];
        command[1]();

        channelsToColors();
        arrayToBitmap(map.moisture, moistureBitmap);
      }

      // Invariant: if _commands is empty, there is no event listener
      if (_commands.length == 0) {
        location_text.text = "(click on minimap to see detail)";
        removeEventListener(Event.ENTER_FRAME, onEnterFrame);
      }
     
      channelsToColors();
      channelsToLighting();
      arrayToBitmap(map.moisture, moistureBitmap);
      arrayToBitmap(map.altitude, altitudeBitmap);
      location_text.text = "(click on minimap to see detail)";
    }
    
    public function arrayToBitmap(v:Vector.<Vector.<int>>, b:BitmapData):void {
      b.lock();
      for (var x:int = 0; x < SIZE; x++) {
        for (var y:int = 0; y < SIZE; y++) {
          var c:int = v[x][y];
          b.setPixel(x, y, (c << 16) | (c << 8) | c);
        }
      }
      b.unlock();
    }


    public function moistureAndAltitudeToColor(m:Number, a:Number, r:Number):int {
      var color:int = 0xff0000;
      
      if (a < OCEAN_ALTITUDE) color = 0x000099;
      //else if (a < OCEAN_ALTITUDE + 3) color = 0xc2bd8c;
      else if (a < OCEAN_ALTITUDE + 5) color = 0xae8c4c;
      else if (a > 220) {
        if (a > 250) color = 0xffffff;
        else if (a > 240) color = 0xeeeeee;
        else if (a > 230) color = 0xddddcc;
        else color = 0xccccaa;
        if (m > 150) color -= 0x331100;
      }

      else if (r > 10) color = 0x00cccc;

      else if (m > 200) color = 0x56821b;
      else if (m > 150) color = 0x3b8c43;
      else if (m > 100)  color = 0x54653c;
      else if (m > 50)  color = 0x334021;
      else if (m > 20)  color = 0x989a2d;
      else              color = 0xc2bd8c;
      
      return color;
    }
    
    public function channelsToColors():void {
      colorMap.lock();
      for (var x:int = 0; x < SIZE; x++) {
        for (var y:int = 0; y < SIZE; y++) {
          colorMap.setPixel
            (x, y,
             moistureAndAltitudeToColor(map.moisture[x][y],
                                        map.altitude[x][y] * (1.0 + 0.1*((x+y)%2)),
                                        map.rivers[x][y]));
        }
      }
      colorMap.unlock();
    }

    public function channelsToLighting():void {
      // From the altitude map, generate a light map that highlights
      // northwest sides of hills. Then blur it all to remove sharp edges.
      lightingMap.lock();
      arrayToBitmap(map.altitude, lightingMap);
      // NOTE: the scale for the lighting should be changed depending
      // on the map size but it's not clear in what way. Alternatively
      // we could rescale the lightingMap to a fixed size and always
      // use that for lighting.
      lightingMap.applyFilter(lightingMap, lightingMap.rect, new Point(0, 0),
                              new ConvolutionFilter
                              (3, 3, [-2, -1, 0,
                                      -1, 0, +1,
                                      0, +1, +2], 2.0, 127));
      lightingMap.applyFilter(lightingMap, lightingMap.rect, new Point(0, 0),
                              new BlurFilter());
      lightingMap.unlock();
    }

    public function generateDetailMap(centerX:Number, centerY:Number):void {
      var NOISESIZE:int = 70;
      var noise:BitmapData = new BitmapData(NOISESIZE, NOISESIZE);
      var noiseScale:int = 1; // out of 128
      noise.noise(map.SEED, 128-noiseScale, 128+noiseScale);

      // We want to fill an area DETAILSIZE x DETAILSIZE by combining
      // the base moisture and altitude levels with the noise function
      // (deterministic, since we use a non-random seed).

      detailMap.fillRect(detailMap.rect, 0xff777777);
      
      // Coordinates of the top left of the detail area:
      var baseX:int = int(centerX * BIGSIZE/SIZE - DETAILSIZE/2);
      var baseY:int = int(centerY * BIGSIZE/SIZE - DETAILSIZE/2);

      // 4-point interpolation function
      function interpolate(A:Vector.<Vector.<int>>, x:Number, y:Number):Number {
        var coarseX:int = int(Math.floor(x));
        var coarseY:int = int(Math.floor(y));
        var fracX:Number = x - coarseX;
        var fracY:Number = y - coarseY;

        return (A[coarseX][coarseY] * (1-fracX) * (1-fracY)
                + A[coarseX+1][coarseY] * fracX * (1-fracY)
                + A[coarseX][coarseY+1] * (1-fracX) * fracY
                + A[coarseX+1][coarseY+1] * fracX * fracY);
      }

      // TODO: this doesn't handle the edges of the map properly
      
      // Go through the detail area and compute each pixel color
      for (var x:int = baseX; x < baseX + DETAILSIZE; x++) {
        for (var y:int = baseY; y < baseY + DETAILSIZE; y++) {
          // The moisture and altitude at x,y will be based on the
          // coarse map, plus the noise scaled by some constant

          var noiseColor:int = noise.getPixel(x % NOISESIZE, y % NOISESIZE);

          var m:Number = interpolate(map.moisture,
                                     x * SIZE/BIGSIZE, y * SIZE/BIGSIZE) + ((noiseColor & 0xff) - 128);
          var a:Number = interpolate(map.altitude,
                                     x * SIZE/BIGSIZE, y * SIZE/BIGSIZE);

          // Make sure that the noise never turns ocean into non-ocean or vice versa
          if (a >= OCEAN_ALTITUDE) {
            a += (((noiseColor >> 8) & 0xff) - 128);
            if (a < OCEAN_ALTITUDE) {
              a = OCEAN_ALTITUDE;
            }
          }
          
          detailMap.setPixel(x - baseX, y - baseY,
                             moistureAndAltitudeToColor(m, a, 0));
        }
      }
    }
  }
}

import flash.display.*;
import flash.geom.*;
import flash.filters.*;

class Map {
  public var SIZE:int;
  public var SEED:int;
  
  public var altitude:Vector.<Vector.<int>>;
  public var moisture:Vector.<Vector.<int>>;
  public var rivers:Vector.<Vector.<int>>;
  
  function Map(size:int, seed:int) {
    SIZE = size;
    SEED = seed;
    altitude = make2dArray(SIZE, SIZE);
    moisture = make2dArray(SIZE, SIZE);
    rivers =  make2dArray(SIZE, SIZE);
  }
  
  public function generate():void {
    // Generate 3-channel perlin noise and copy 2 of the channels out
    var b:BitmapData = new BitmapData(SIZE, SIZE);
    b.perlinNoise(SIZE, SIZE, 8, SEED, false, false);
    
    var s:Shape = new Shape();
    
    equalizeTerrain(b);
    
    var m:Matrix = new Matrix();
    m.createGradientBox(SIZE, SIZE, 0, 0, 0);
    s.graphics.beginGradientFill(GradientType.RADIAL,
                                 [0x000000, 0x000000],
                                 [0.0, 0.3],
                                 [0x00, 0xff],
                                 m,
                                 SpreadMethod.PAD);
    s.graphics.drawRect(0, 0, SIZE, SIZE);
    s.graphics.endFill();
    b.draw(s);
    
    /*
      s.graphics.clear();
      s.graphics.beginFill(0xffffff, 0.0);
      s.graphics.drawRect(10, 10, SIZE-2*10, SIZE-2*10);
      s.graphics.endFill();
      b.draw(s);
    */
    
    equalizeTerrain(b);
    
    
    // Extract information from bitmap
    for (var x:int = 0; x < SIZE; x++) {
      for (var y:int = 0; y < SIZE; y++) {
        var c:int = b.getPixel(x, y);
        altitude[x][y] = (c >> 8) & 0xff;
        moisture[x][y] = c & 0xff;
      }
    }
  }
  
  public function equalizeTerrain(bitmap:BitmapData):void {
    // Adjust altitude histogram so that it's roughly quadratic and
    // water histogram so that it's roughly linear
    var histograms:Vector.<Vector.<Number>> = bitmap.histogram(bitmap.rect);
    var G:Vector.<Number> = histograms[1];
    var B:Vector.<Number> = histograms[2];
    var g:int = 0;
    var b:int = 0;
    var green:Array = new Array(256);
    var blue:Array = new Array(256);
    var cumsumG:Number = 0.0;
    var cumsumB:Number = 0.0;
    for (var i:int = 0; i < 256; i++) {
      cumsumG += G[i];
      cumsumB += B[i];
      green[i] = (g*g/255) << 8; // int to green color value
      blue[i] = (b*b/255); // int to blue color value
      while (cumsumG > SIZE*SIZE*Math.sqrt(g/256.0) && g < 255) {
        g++;
      }
      while (cumsumB > SIZE*SIZE*(b/256.0) && b < 255) {
        b++;
      }
    }
    bitmap.paletteMap(bitmap, bitmap.rect, new Point(0, 0), null, green, blue, null);
    
    // Blur everything because the quadratic shift introduces
    // discreteness -- ick!!  TODO: probably better to apply the
    // histogram correction after we convert to the altitude[]
    // array, although even there it's already been discretized :(
    bitmap.applyFilter(bitmap, bitmap.rect, new Point(0, 0), new BlurFilter());

    // TODO: if we ever want to run equalizeTerrain after
    // spreadMoisture, we need to special-case water=255 (leave it alone)
  }
  
  public function make2dArray(w:int, h:int):Vector.<Vector.<int>> {
    var v:Vector.<Vector.<int>> = new Vector.<Vector.<int>>(w);
    for (var x:int = 0; x < w; x++) {
      v[x] = new Vector.<int>(h);
      for (var y:int = 0; y < h; y++) {
        v[x][y] = 0;
      }
    }
    return v;
  }
  
  public function blurMoisture():void {
    // Note: this isn't scale-independent :(
    var radius:int = 1;
    var result:Vector.<Vector.<int>> = make2dArray(SIZE, SIZE);
    
    for (var x:int = 0; x < SIZE; x++) {
      for (var y:int = 0; y < SIZE; y++) {
        var numer:int = 0;
        var denom:int = 0;
        for (var dx:int = -radius; dx <= +radius; dx++) {
          for (var dy:int = -radius; dy <= +radius; dy++) {
            if (0 <= x+dx && x+dx < SIZE && 0 <= y+dy && y+dy < SIZE) {
              numer += moisture[x+dx][y+dy];
              denom += 1;
            }
          }
        }
        result[x][y] = numer / denom;
      }
    }
    moisture = result;
  }
  
  public function spreadMoisture():void {
    var windX:Number = 250.0 * SIZE/mapgen.BIGSIZE;
    var windY:Number = 120.0 * SIZE/mapgen.BIGSIZE;
    var evaporation:int = 1;
    
    var result:Vector.<Vector.<int>> = make2dArray(SIZE, SIZE);
    for (var x:int = 0; x < SIZE; x++) {
      for (var y:int = 0; y < SIZE; y++) {
        if (altitude[x][y] < mapgen.OCEAN_ALTITUDE) {
          result[x][y] += 255; // ocean
        }
        
        result[x][y] += moisture[x][y] - evaporation;

        var wx:Number = 0.1 * (8.0 + Math.random() + Math.random());
        var wy:Number = 0.1 * (8.0 + Math.random() + Math.random());
        var x2:int = x + int(windX * wx);
        var y2:int = y + int(windY * wy);
        x2 %= SIZE; y2 %= SIZE;
        if (x != x2 && y != y2) {
          var transfer:int = moisture[x][y]/3;
          var speed:Number = (30.0 + altitude[x][y]) / (30.0 + altitude[x2][y2]);
          if (speed > 1.0) speed = 1.0;
          /* speed is lower if going uphill */
          transfer = int(transfer * speed);
          
          result[x][y] -= transfer;
          result[x2][y2] += transfer;
        }
      }
    }

    for (x = 0; x < SIZE; x++) {
      for (y = 0; y < SIZE; y++) {
        if (result[x][y] < 0) result[x][y] = 0;
        if (result[x][y] > 255) result[x][y] = 255;
      }
    }
    
    moisture = result;
  }

  public function carveCanyons():void {
    for (var iteration:int = 0; iteration < 10000; iteration++) {
      var x:int = int(Math.floor(SIZE*Math.random()));
      var y:int = int(Math.floor(SIZE*Math.random()));

      for (var trail:int = 0; trail < 1000; trail++) {
        // Just quit at the boundaries
        if (x == 0 || x == SIZE-1 || y == 0 || y == SIZE-1) {
          break;
        }

        // Find the minimum neighbor
        var x2:int = x, y2:int = y;
        for (var dx:int = -1; dx <= +1; dx++) {
          for (var dy:int = -1; dy <= +1; dy++) {
            if (altitude[x+dx][y+dy] < altitude[x2][y2]) {
              x2 = x+dx; y2 = y+dy;
            }
          }
        }

        // TODO: make the river keep going to the ocean no matter what!
        
        // Move the particle in that direction, and remove some land
        if (x == x2 && y == y2) {
          if (altitude[x][y] < 10) break;
          // altitude[x][y] = Math.min(255, altitude[x][y] + trail);
        }
        x = x2; y = y2;
        altitude[x][y] = Math.max(0, altitude[x][y] - 1);
        rivers[x][y] += 1;
      }
    }

    for (x = 0; x < SIZE; x++) {
      for (y = 0; y < SIZE; y++) {
        if (rivers[x][y] > 100) moisture[x][y] = 255;
      }
    }
  }
}

