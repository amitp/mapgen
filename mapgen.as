// Generate a fantasy-world map
// Author: amitp@cs.stanford.edu
// License: MIT

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
    // NOTE: some sort of bug is triggered for seed 77904, leading to craters on the map
    public static var OCEAN_ALTITUDE:int = 1;
    public static var SIZE:int = 512;
    public static var DETAILSIZE:int = 64;
    public static var DETAILMAG:int = 8;
    
    // Smooth color mode uses a continuous function for non-sand,
    // non-water terrain; the regular mode uses discrete terrain
    // types. Smooth coloring doesn't work well with the smoothing
    // from vertex displacement.
    public static var useSmoothColors:Boolean = false;
    
    public var seed_text:TextField = new TextField();
    public var seed_button:TextField = new TextField();
    public var save_altitude_button:TextField = new TextField();
    public var save_moisture_button:TextField = new TextField();
    public var location_text:TextField = new TextField();
    public var moisture_iterations:TextField = new TextField();
    public var generate_button:TextField = new TextField();

    public var corner_adjust_text:TextField = new TextField();
    public var random_adjust_text:TextField = new TextField();
      
    public var map:Map = new Map(SIZE, SEED);
    public var colorMap:BitmapData;
    public var lightingMap:BitmapData;
    public var moistureBitmap:BitmapData;
    public var altitudeBitmap:BitmapData;

    public var detailMap:Shape = new Shape();
    
    [Embed("oryx/lofi_environment_a.png")]
      public const lofi_environment_a:Class;
    public var sprites:Bitmap = new lofi_environment_a();
    
    public function mapgen() {
      colorMap = new BitmapData(256, 256);
      lightingMap = new BitmapData(256, 256);
      moistureBitmap = new BitmapData(SIZE, SIZE);
      altitudeBitmap = new BitmapData(SIZE, SIZE);
      
      stage.scaleMode = "noScale";
      stage.align = "TL";
      stage.frameRate = 60;
      
      addChild(new Debug(this));
      
      graphics.beginFill(0xffffff);
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
        field.backgroundColor = 0xccccdd;
        field.autoSize = TextFieldAutoSize.LEFT;
        field.type = TextFieldType.INPUT;
      }
      
      function changeIntoButton(button:TextField, text:String):void {
        button.text = text;
        button.background = true;
        button.backgroundColor = 0xbbddbb;
        button.selectable = false;
        button.autoSize = TextFieldAutoSize.LEFT;
        button.filters = [new BevelFilter(1)];
      }

      addChild(createLabel("Generating maps of size "
                           + SIZE + "x" + SIZE, 255, 2));
      addChild(createLabel("Amit J Patel -- "
                          + "http://simblob.blogspot.com/", 260+512, 515));
      
      changeIntoEditable(seed_text, "" + SEED);
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
                                         SEED = int(seed_text.text);
                                         newMap();
                                       });
      addChild(generate_button);

      changeIntoButton(seed_button, " Randomize ");
      seed_button.x = 20;
      seed_button.y = 70;
      seed_button.addEventListener(MouseEvent.MOUSE_UP,
                                   function (e:Event):void {
                                     SEED = int(100000*Math.random());
                                     seed_text.text = "" + SEED;
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

      var b:Bitmap = new Bitmap(moistureBitmap);
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

      changeIntoEditable(corner_adjust_text, "0.25");
      corner_adjust_text.restrict = "0-9.";
      corner_adjust_text.x = 220;
      corner_adjust_text.y = 60;
      addChild(corner_adjust_text);
      addChild(createLabel("Corner:", 200, 60));
               
      changeIntoEditable(random_adjust_text, "0.00");
      random_adjust_text.restrict = "0-9.";
      random_adjust_text.x = 220;
      random_adjust_text.y = 80;
      addChild(random_adjust_text);
      addChild(createLabel("Random:", 200, 80));
               
      detailMap.x = 260;
      detailMap.y = 0;
      addChild(detailMap);
      
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
      // Rescale the mouse click from the minimap size to the internal map size
      var x:Number = event.localX * map.SIZE / colorMap.width;
      var y:Number = event.localY * map.SIZE / colorMap.height;
      location_text.text = "Map @ " + x + ", " + y;
      generateDetailMap(detailMap.graphics, x, y);
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
                           map.blurMoisture();
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
    }
    
    public function arrayToBitmap(v:Vector.<Vector.<int>>, b:BitmapData):void {
      b.lock();
      for (var x:int = 0; x < v.length; x++) {
        for (var y:int = 0; y < v[x].length; y++) {
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
      else if (useSmoothColors) {
        color = Color.hsvToRgb(40.0 + 100.0 * m/255 + 30 * Math.min(a,m)/255,
                               0.8+0.2*m/255-0.7*a/255,
                               0.5+0.5*a/255-0.3*m/255);
      } else if (a > 220) {
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
      var b:BitmapData = new BitmapData(map.SIZE, map.SIZE);
      for (var x:int = 0; x < map.SIZE; x++) {
        for (var y:int = 0; y < map.SIZE; y++) {
          b.setPixel
            (x, y,
             moistureAndAltitudeToColor(map.moisture[x][y],
                                        map.altitude[x][y] * (1.0 + 0.1*((x+y)%2)),
                                        map.rivers[x][y]));
        }
      }

      var m:Matrix = new Matrix();
      m.scale(colorMap.width / b.width, colorMap.height / b.height);
      colorMap.draw(b, m, null, null, null, true);
    }

    public function channelsToLighting():void {
      // From the altitude map, generate a light map that highlights
      // northwest sides of hills. Then blur it all to remove sharp edges.
      var b:BitmapData = new BitmapData(map.SIZE, map.SIZE);
      arrayToBitmap(map.altitude, b);
      // NOTE: the scale for the lighting should be changed depending
      // on the map size but it's not clear in what way. Alternatively
      // we could rescale the lightingMap to a fixed size and always
      // use that for lighting.
      b.applyFilter(b, b.rect, new Point(0, 0),
                    new ConvolutionFilter
                    (3, 3, [-2, -1, 0,
                            -1, 0, +1,
                            0, +1, +2], 2.0, 127));
      b.applyFilter(b, b.rect, new Point(0, 0),
                    new BlurFilter());
      
      var m:Matrix = new Matrix();
      m.scale(lightingMap.width / b.width, lightingMap.height / b.height);
      lightingMap.draw(b, m);
    }

    public function generateDetailMap(g: Graphics, centerX:Number, centerY:Number):void {
      // Parameters
      var cornerAdjust:Number = DETAILMAG*Number(corner_adjust_text.text);
      var randomAdjust:Number = DETAILMAG*Number(random_adjust_text.text);
      
      // We are drawing an area DETAILSIZE x DETAILSIZE.
      var x:int, y:int;
      g.clear();
      
      // Coordinates of the detail area:
      var bounds:Rectangle = new Rectangle
        (int(centerX  - DETAILSIZE/2), int(centerY - DETAILSIZE/2),
         DETAILSIZE, DETAILSIZE);

      // Make sure that we're entirely within the bounds of the map
      bounds = bounds.intersection(new Rectangle(0, 0, SIZE, SIZE));
      
      // 2d Array of vertices
      var vertices:Array = [];
      for (x = bounds.left; x <= bounds.right; x++) {
        vertices[x] = [];
        for (y = bounds.top; y <= bounds.bottom; y++) {
          // TODO: we'd save a lot of allocation if we reused these points
          vertices[x][y] = new Point((x-centerX+DETAILSIZE/2)*DETAILMAG,
                                     (y-centerY+DETAILSIZE/2)*DETAILMAG);
        }
      }

      // Move vertices randomly
      var noise:BitmapData = new BitmapData(256, 256);
      noise.noise(SEED, 0, 255);
      for (x = bounds.left; x <= bounds.right; x++) {
        for (y = bounds.top; y <= bounds.bottom; y++) {
          var noiseColor:int = noise.getPixel(x % 256, y % 256);
          var rand1:Number = ((noiseColor & 0x00ff00) >> 8) / 255.0 - 0.5;
          var rand2:Number = (noiseColor & 0xff) / 255.0 - 0.5;
          vertices[x][y].x += rand1 * randomAdjust;
          vertices[x][y].y += rand2 * randomAdjust;
        }
      }
      
      // Alter vertices if 3 of 4 squares has same type
      for (x = bounds.left+1; x < bounds.right; x++) {
        for (y = bounds.top+1; y < bounds.bottom; y++) {
          // Sprites at the four squares touching this vertex
          var cTL:int = moistureAndAltitudeToColor(map.moisture[x-1][y-1], map.altitude[x-1][y-1], 0);
          var cTR:int = moistureAndAltitudeToColor(map.moisture[x][y-1], map.altitude[x][y-1], 0);
          var cBL:int = moistureAndAltitudeToColor(map.moisture[x-1][y], map.altitude[x-1][y], 0);
          var cBR:int = moistureAndAltitudeToColor(map.moisture[x][y], map.altitude[x][y], 0);

          // Figure out which corner is odd, if any 
          if (cTR == cBL && cBL == cBR && cTL != cTR) {  // TL is odd
            vertices[x][y].x -= cornerAdjust;
            vertices[x][y].y -= cornerAdjust;
          }
          if (cTL == cTR && cTR == cBL && cBL != cBR) {  // BR is odd
            vertices[x][y].x += cornerAdjust;
            vertices[x][y].y += cornerAdjust;
          }
          if (cTL == cBL && cBL == cBR && cTL != cTR) {  // TR is odd
            vertices[x][y].x += cornerAdjust;
            vertices[x][y].y -= cornerAdjust;
          }
          if (cTL == cTR && cTR == cBR && cTL != cBL) {  // BL is odd
            vertices[x][y].x -= cornerAdjust;
            vertices[x][y].y += cornerAdjust;
          }
          // TODO: this seems like stupid repetitive code TODO: what
          // should we do when we have tiles A A B C (A and A are
          // adjacent but only two of them)?
        }
      }
      
      // Draw grid
      // g.lineStyle(1, 0x000000, 0.1);   // TODO: set border if tiles not the same
      var m:Matrix = new Matrix();
      for (x = bounds.left; x < bounds.right; x++) {
        for (y = bounds.top; y < bounds.bottom; y++) {
          // TODO: we should have cached the tile ids when we generate the map...
          var c:int = moistureAndAltitudeToColor(map.moisture[x][y],
                                                 map.altitude[x][y], 0);
          g.beginFill(c);
          g.moveTo(vertices[x][y].x, vertices[x][y].y);
          g.lineTo(vertices[x][y+1].x, vertices[x][y+1].y);
          g.lineTo(vertices[x+1][y+1].x, vertices[x+1][y+1].y);
          g.lineTo(vertices[x+1][y].x, vertices[x+1][y].y);
          g.lineTo(vertices[x][y].x, vertices[x][y].y);
          g.endFill();
        }
      }
      g.lineStyle();
    }
  }
}

import flash.display.*;
import flash.geom.*;
import flash.filters.*;

class Map {
  // Make the map into an island.  0.39 makes almost every map into an
  // island; 0.1 makes almost no map into an island.
  public static var ISLAND_EFFECT:Number = 0.39;
  
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

    // NOTE: if we remembered the equalization and other parameters,
    // we could zoom in at least on the altitude map by using the
    // perlinNoise() size and offsets parameters to regenerate
    // portions of the map at higher resolution. This could be useful
    // when drawing the detail map.
    equalizeTerrain(b);

    // Overlay this on an "island" multiplier map
    // Based on http://www.ridgenet.net/~jslayton/FunWithWilburVol6/index.html
    for (x = 0; x < SIZE; x++) {
      for (y= 0; y < SIZE; y++) {
        var radiusSquared:Number = (x-SIZE/2)*(x-SIZE/2) + (y-SIZE/2)*(y-SIZE/2);
        radiusSquared += Math.pow(Math.max(Math.abs(x-SIZE/2), Math.abs(y-SIZE/2)), 2);
        var max_radiusSquared:Number = SIZE*SIZE/4;
        radiusSquared /= max_radiusSquared;
        radiusSquared += Math.random() * 0.1;
        radiusSquared *= ISLAND_EFFECT; 
        var island_multiplier:Number = Math.exp(-radiusSquared/4)-radiusSquared;
        island_multiplier = island_multiplier * island_multiplier * island_multiplier;
        // island_multiplier = island_multiplier * island_multiplier * island_multiplier;

        c = b.getPixel(x, y);
        var height:int = (c >> 8) & 0xff;
        height = int(island_multiplier * height);
        if (height < 0) height = 0;
        if (height > 255) height = 255;
        c = (c & 0xffff00ff) | (height << 8);
        b.setPixel(x, y, c);
      }
    }

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
    var windX:Number = SIZE/17.0;
    var windY:Number = SIZE/23.0;
    var evaporation:int = 1;
    
    var result:Vector.<Vector.<int>> = make2dArray(SIZE, SIZE);
    for (var x:int = 0; x < SIZE; x++) {
      for (var y:int = 0; y < SIZE; y++) {
        if (altitude[x][y] < mapgen.OCEAN_ALTITUDE) {
          result[x][y] += 255; // ocean
        }
        
        result[x][y] += moisture[x][y] - evaporation;

        // Dampen the randomness
        var wx:Number = (20.0 + Math.random() + Math.random()) / 21.0;
        var wy:Number = (20.0 + Math.random() + Math.random()) / 21.0;
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

