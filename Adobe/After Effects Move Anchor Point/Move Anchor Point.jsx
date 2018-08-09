// Move Anchor Point Version 2.0
// An After Effects Script by Jesse Toula
// BatchFrame.com 2013 

// I would like to thank Oplique  for helping me to test and improve this script

var w = (this instanceof Panel) ? this : new Window("palette", "Move Anchor Point", undefined, {resizeable: true}); // Check if the call is from the Window menu, otherwise create the window

// create a group
w.g = w.add("group", [10,0,85,75]);
w.orientation = "row";


try {
    
// button image files
// My plan for version 2 wad to embed the image files so
// you would no longer need the map_images folder,
// however there seems to be a bug in the newest update of AE
// that causes an error when loading embedded images. So
// for now, we will reference them in a separate folder. The file path 
// is relative to the location of the script.

var tli = File("map_images/tli.png");
var tmi = File("map_images/tmi.png");
var tri = File("map_images/tri.png");
var mli = File("map_images/mli.png");
var mmi = File("map_images/mmi.png");
var mri = File("map_images/mri.png");
var bli = File("map_images/bli.png");
var bmi = File("map_images/bmi.png");
var bri = File("map_images/bri.png");


// This is all the Script UI, creating the interface.
// top row
w.g.tg = w.g.add("group", [0,0,75,25]);
w.g.tg.orientation = "row";
w.g.tg.tl = w.g.tg.add("iconbutton", [0,0,25,25],  tli, {style: "toolbutton"});
w.g.tg.tm = w.g.tg.add("iconbutton", [25,0,50,25], tmi, {style: "toolbutton"});
w.g.tg.tr = w.g.tg.add("iconbutton", [50,0,75,25], tri, {style: "toolbutton"});

// middle row
w.g.mg = w.g.add("group", [0,25,75,50]);
w.g.mg.orientation = "row";
w.g.mg.tl = w.g.mg.add("iconbutton", [0,0,25,25], mli, {style: "toolbutton"});
w.g.mg.tm = w.g.mg.add("iconbutton", [25,0,50,25], mmi, {style: "toolbutton"});
w.g.mg.tr = w.g.mg.add("iconbutton", [50,0,75,25], mri, {style: "toolbutton"});

// bottom row
w.g.bg = w.g.add("group", [0,50,75,75]);
w.g.bg.orientation = "row";
w.g.bg.tl = w.g.bg.add("iconbutton", [0,0,25,25], bli, {style: "toolbutton"});
w.g.bg.tm = w.g.bg.add("iconbutton", [25,0,50,25], bmi, {style: "toolbutton"});
w.g.bg.tr = w.g.bg.add("iconbutton", [50,0,75,25], bri, {style: "toolbutton"});

} catch(err) {
        // if the image folder is not in the correct location,
        // the script will not work and AE will return an error.
        // The error that AE give by default does not explain
        // the problem, so this alert will give the user a reason
        // for, and solution to the problem
        alert("The 'map_images' folder is not in the same location as the 'Move Anchor Point.jsx'. Please correct this in order to use Move Anchor Point. Consult the readMe if you need assistance.");
}

// this is the custom point section of th interface
w.g2 = w.add("group", [95,0,270,75]);
w.g2.stx = w.g2.add("statictext", [0,7,10,25], "X:")
w.g2.tx = w.g2.add("edittext", [15,5,85,25],".5")
w.g2.stx = w.g2.add("statictext", [90,7,100,25], "Y:")
w.g2.ty = w.g2.add("edittext", [105,5,175,25],".5")
w.g2.b = w.g2.add("button", [0,40,175,70], "Move to Custom Point");

// this is the ignore masks checkbox
w.im = w.add("checkbox", [10,80,110,95], "Ignore Masks");

// in CS6 I was having issues with just writing w.show()
// so now I am checking weather the script was run from the window menu or the File>Script menu
// If it is from the script menu, it will show the panel, otherwise it is already shown.
if (!(this instanceof Panel)) {
        w.show();
}


// set up button clicks. Each button calls the moveAnchor
// function that uses simple coordinates to represent the 
// different anchor point positions. 0 = top or left, 1 = middle
// 2 = bottom or right
// In version 2, Three new arguments were added to the moveAnchor function
// the first is Ignore Masks. It passes either true or false. The second two are the 
// custom X and Y points. You can see that only the last line uses the custom points.
w.g.tg.tl.onClick = function() {app.beginUndoGroup("Move Anchor - Top Left"); moveAnchor(0,0,w.im.value); app.endUndoGroup();}
w.g.tg.tm.onClick = function() {app.beginUndoGroup("Move Anchor - Top Middle"); moveAnchor(1,0,w.im.value); app.endUndoGroup();}
w.g.tg.tr.onClick = function() {app.beginUndoGroup("Move Anchor - Top Right"); moveAnchor(2,0,w.im.value); app.endUndoGroup();}

w.g.mg.tl.onClick = function() {app.beginUndoGroup("Move Anchor - Middle Left"); moveAnchor(0,1,w.im.value); app.endUndoGroup();}
w.g.mg.tm.onClick = function() {app.beginUndoGroup("Move Anchor - Middle Middle"); moveAnchor(1,1,w.im.value); app.endUndoGroup();}
w.g.mg.tr.onClick = function() {app.beginUndoGroup("Move Anchor - Middle Right"); moveAnchor(2,1,w.im.value); app.endUndoGroup();}

w.g.bg.tl.onClick = function() {app.beginUndoGroup("Move Anchor - Bottom Left"); moveAnchor(0,2,w.im.value); app.endUndoGroup();}
w.g.bg.tm.onClick = function() {app.beginUndoGroup("Move Anchor - Bottom Middle"); moveAnchor(1,2,w.im.value); app.endUndoGroup();}
w.g.bg.tr.onClick = function() {app.beginUndoGroup("Move Anchor - Bottom Right"); moveAnchor(2,2,w.im.value); app.endUndoGroup();}

w.g2.b.onClick = function() {app.beginUndoGroup("Move Anchor - Custom"); moveAnchor(3,3,w.im.value, eval(w.g2.tx.text),eval(w.g2.ty.text)); app.endUndoGroup();}



//Move Anchor Function
function moveAnchor(row, col, ignoreMasks, cust1, cust2) {
    // get the current position of the time indicator
    var curTime = app.project.activeItem.time;
    
    // put all selected layers into a vaiable. This vaiable will contain
    // an array of layers.
    var theLayers = app.project.activeItem.selectedLayers; 
    
    // make sure there are layers selected. If the 'theLayers' array
    // has a length of 0, it does not contain any layers, meaning there
    // are no layers selected
    if (theLayers.length == 0) {
        alert("You do not have any layers selected");
        // return will cause the script to exit the function
        return;
    }

    // loop through for eac hselected layer
    for (num = 0; num < theLayers.length; num++) {
        // set the a variable to the current layer
        var theLayer = theLayers[num];
        
        // check if a camera layer is a camera
        if (theLayer instanceof CameraLayer) {
            // if the only layer selected is a camera layer, alert the user
            // otherwise just skip over it
            if (theLayers.length == 1) {
                alert("Move Anchor Point will not change the anchor point of a camera");
            }
            // continue tells the script to skip the rest of the loop
            // and move on to the next iteration
            continue;
        }

       
        // set a vairable to alert whether or not there are masks.
        // By default we will assume no masks, then change it to 
        // false if we find any
        var noMasks = true;
        
        // if the user checked 'Ignore Masks' then we will run the script
        // as if there are none and  the noMasks variable will remain
        // true automatically
        if (ignoreMasks == true) {
            noMasks = true
        } else {
            // if there are masks, then we will check if the mask type is NONE.
            // If there is a mask and the type is not NONE, we will change
            // noMasks to false.
            if (theLayer.mask.numProperties != 0)  {
                for (var i = 1; i <= theLayer.mask.numProperties; i++) {
                        if (theLayer.mask(i).maskMode != MaskMode.NONE) {
                            noMasks = false;
                        }
                }
            }
       }

        
        if (noMasks) {
            // If the value is 0, set the anchor to 0.
            // if the value is 1, set the anchor to half of the layer width/height
            // if the value is 2, set the anchor to the width/height of the layer
            // case 3 was added in version 2 for if a user clicks on the
            // move to custom point button
            switch (row) {
                case 0:
                    var x = 0;
                    break;
                case 1:
                    var x = (theLayer.sourceRectAtTime(curTime, false).width/2);
                    break;
                case 2:
                    var x = (theLayer.sourceRectAtTime(curTime, false).width);
                    break;
                case 3:
                    var x = (theLayer.sourceRectAtTime(curTime, false).width*cust1);
                    break;
                default:
            }
            
            switch (col) {
                case 0:
                    var y = 0;
                    break;
                case 1:
                    var y = (theLayer.sourceRectAtTime(curTime, false).height/2);
                    break;
                case 2:
                    var y = (theLayer.sourceRectAtTime(curTime, false).height); 
                    break;
                case 3:
                    var y = (theLayer.sourceRectAtTime(curTime, false).height*cust2);
                    break;
                default:
            }
        
             // if the layer is a text or shape layer, the anchor point's origin
            // is not at the top left corner. Correct for this by moving the x 
            // and y points to the top left. 
            // .sourceRectAtTime() allows you to get the actual sie of the layer
            // for instance, a text layers width is equal to the width of the
            // composition, even if the text is not that long. Using
            // sourceRectAtTime allows to you get the visible width and height
            if (theLayer instanceof TextLayer || theLayer instanceof ShapeLayer) {
                x += theLayer.sourceRectAtTime(curTime, false).left;
                y += theLayer.sourceRectAtTime(curTime, false).top;
            }      
        
        } else {
            // if the layer has masks applied, we must find the new dimensions of the layer first
            // there is not a simple way to do this. We must find the highest and lowest X and Y coordinates for 
            // each mask applied to the layer, then work based off those dimensions.

            // vars to hold vert arrays
            var xBounds = Array();
            var yBounds = Array();
            var numMasks = theLayer.mask.numProperties;

            for (var i = 1; i <= numMasks; i++) {
                var numVerts = theLayer.mask(i).maskShape.value.vertices.length;
                if(theLayer.mask(i).maskMode == MaskMode.NONE) {continue;}
                for (var j = 0; j < numVerts; j++) {
                    var curVerts = theLayer.mask(i).maskShape.valueAtTime(curTime,false).vertices[j];
                    xBounds.push(curVerts[0])
                    yBounds.push(curVerts[1])
                }
            }

            // sort arrays low to high, then get the highest and lowest of each
            xBounds.sort(function(a,b){return a-b})
            yBounds.sort(function(a,b){return a-b})

            var xl = xBounds.shift();
            var xh = xBounds.pop();
            var yl = yBounds.shift();
            var yh = yBounds.pop();   
            
             if (theLayer instanceof TextLayer || theLayer instanceof ShapeLayer) {
               var xl2 = theLayer.sourceRectAtTime(curTime, false).left;
               var xh2 = xl2 + theLayer.sourceRectAtTime(curTime, false).width;
               var yl2 = theLayer.sourceRectAtTime(curTime, false).top;
               var yh2 = yl2 + theLayer.sourceRectAtTime(curTime, false).height;
               
               if (xl < xl2) {xl = xl2;}
               if (xh > xh2) {xh = xh2;}
               if (yl < yl2) {yl = yl2;}
               if (yh > yh2) {yh = yh2;}
            } 
            
            switch (row) {
                case 0:
                    var x = xl;
                    break;
                case 1:
                    var x = xl + ((xh-xl)/2);
                    break;
                case 2:
                    var x = xh;
                    break;
                case 3:
                    var x = xl + ((xh-xl)*cust1);
                    break;
                default:
            }
            
            switch (col) {
                case 0:
                    var y = yl;
                    break;
                case 1:
                    var y = yl + ((yh-yl)/2);
                    break;
                case 2:
                    var y = yh; 
                    break;
                case 3:
                    var y = yl + ((yh-yl)*cust2);
                    break;
                default:
            }
        }
    
         
        
        // check if the anchor point has keyframes
        if (theLayer.anchorPoint.isTimeVarying) {
            // if ther layer does have anchor point keyframes,
            // just set a new keyframe for the desired point, no
            // position correction is applied
            theComp = app.project.activeItem;
            theLayer.anchorPoint.setValueAtTime(theComp.time, [x,y]);
        } else {
            // set a variable equal to the current anchorPoint
            var curAnchor = theLayer.anchorPoint.value;
            
            // calculate the change in the position that will be needed to
            // keep the layer in the same spot after changing the anchor point.
            // The move is multiplied by the scale percentage to correct for
            // layers that have been scalled
            var xMove = (x - curAnchor[0]) * (theLayer.scale.value[0]/100);
            var yMove = (y - curAnchor[1])  * (theLayer.scale.value[1]/100);
            
            var posEx = false;
            if(theLayer.position.expressionEnabled) {
                theLayer.position.expressionEnabled = false;
                posEx = true;
            }
            
            // in order to maintain the proper positions, I found it was best to 
            // move the layer relative to itself, not the world. In order to do this,
            // we must parent the layer to a duplicate of itself.
            var dupLayer = theLayer.duplicate();
            // in case the layer already has a oarent, wel wil store that value
            // and use it to reset the layer after the anchor point has been moved.
            var oldParent = theLayer.parent;
            // move the duplicate layer to the end to avoid messing with
            //expressions in the comp.
            dupLayer.moveToEnd();
            if (dupLayer.scale.isTimeVarying) {
                dupLayer.scale.setValueAtTime(app.project.activeItem.time, [100,100])
            } else {
                dupLayer.scale.setValue([100,100]);
            }
            
            // set the new parent
            theLayer.parent = dupLayer;
            
            // change the anchor point of the current layer
            theLayer.anchorPoint.setValue([x,y]);
            
            // this is inside the anchor point if statement because if the 
            // anchor point has keyframes, I am not going to change
            // the position of the layer
            
            // check if the current layer has position keyframes
            if (theLayer.position.isTimeVarying) {
                var numKeys = theLayer.position.numKeys;
                
                // move the layer for each position keyframe to correct
                // for the anchor point change
                for (var k = 1; k <= numKeys; k++) {
                    var curPos = theLayer.position.keyValue(k);
                    curPos[0] += xMove;
                    curPos[1] += yMove;
                    theLayer.position.setValueAtKey(k, curPos);
                }
            } else {
                // in this case there are no keyframes on the positoins
                // so we just store the single position value in a variable
                var curPos = theLayer.position.value;
                
                // then add the xMove andyMove values to their respective
                // position values
                theLayer.position.setValue([curPos[0] + xMove,curPos[1] + yMove, curPos[2]]); 
     
            }
            // reset the parent of the changed layer
            theLayer.parent = oldParent;
            if(posEx) {
                theLayer.position.expressionEnabled = true;
            }

            
            // remove the duplicate layer that was used for parenting
            dupLayer.remove();
        }
    }
}