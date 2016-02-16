(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(_dereq_,module,exports){
var foograph = {
  /**
   * Insert a vertex into this graph.
   *
   * @param vertex A valid Vertex instance
   */
  insertVertex: function(vertex) {
      this.vertices.push(vertex);
      this.vertexCount++;
    },

  /**
   * Insert an edge vertex1 --> vertex2.
   *
   * @param label Label for this edge
   * @param weight Weight of this edge
   * @param vertex1 Starting Vertex instance
   * @param vertex2 Ending Vertex instance
   * @return Newly created Edge instance
   */
  insertEdge: function(label, weight, vertex1, vertex2, style) {
      var e1 = new foograph.Edge(label, weight, vertex2, style);
      var e2 = new foograph.Edge(null, weight, vertex1, null);

      vertex1.edges.push(e1);
      vertex2.reverseEdges.push(e2);

      return e1;
    },

  /**
   * Delete edge.
   *
   * @param vertex Starting vertex
   * @param edge Edge to remove
   */
  removeEdge: function(vertex1, vertex2) {
      for (var i = vertex1.edges.length - 1; i >= 0; i--) {
        if (vertex1.edges[i].endVertex == vertex2) {
          vertex1.edges.splice(i,1);
          break;
        }
      }

      for (var i = vertex2.reverseEdges.length - 1; i >= 0; i--) {
        if (vertex2.reverseEdges[i].endVertex == vertex1) {
          vertex2.reverseEdges.splice(i,1);
          break;
        }
      }
    },

  /**
   * Delete vertex.
   *
   * @param vertex Vertex to remove from the graph
   */
  removeVertex: function(vertex) {
      for (var i = vertex.edges.length - 1; i >= 0; i-- ) {
        this.removeEdge(vertex, vertex.edges[i].endVertex);
      }

      for (var i = vertex.reverseEdges.length - 1; i >= 0; i-- ) {
        this.removeEdge(vertex.reverseEdges[i].endVertex, vertex);
      }

      for (var i = this.vertices.length - 1; i >= 0; i-- ) {
        if (this.vertices[i] == vertex) {
          this.vertices.splice(i,1);
          break;
        }
      }

      this.vertexCount--;
    },

  /**
   * Plots this graph to a canvas.
   *
   * @param canvas A proper canvas instance
   */
  plot: function(canvas) {
      var i = 0;
      /* Draw edges first */
      for (i = 0; i < this.vertices.length; i++) {
        var v = this.vertices[i];
        if (!v.hidden) {
          for (var j = 0; j < v.edges.length; j++) {
            var e = v.edges[j];
            /* Draw edge (if not hidden) */
            if (!e.hidden)
              e.draw(canvas, v);
          }
        }
      }

      /* Draw the vertices. */
      for (i = 0; i < this.vertices.length; i++) {
        v = this.vertices[i];

        /* Draw vertex (if not hidden) */
        if (!v.hidden)
          v.draw(canvas);
      }
    },

  /**
   * Graph object constructor.
   *
   * @param label Label of this graph
   * @param directed true or false
   */
  Graph: function (label, directed) {
      /* Fields. */
      this.label = label;
      this.vertices = new Array();
      this.directed = directed;
      this.vertexCount = 0;

      /* Graph methods. */
      this.insertVertex = foograph.insertVertex;
      this.removeVertex = foograph.removeVertex;
      this.insertEdge = foograph.insertEdge;
      this.removeEdge = foograph.removeEdge;
      this.plot = foograph.plot;
    },

  /**
   * Vertex object constructor.
   *
   * @param label Label of this vertex
   * @param next Reference to the next vertex of this graph
   * @param firstEdge First edge of a linked list of edges
   */
  Vertex: function(label, x, y, style) {
      this.label = label;
      this.edges = new Array();
      this.reverseEdges = new Array();
      this.x = x;
      this.y = y;
      this.dx = 0;
      this.dy = 0;
      this.level = -1;
      this.numberOfParents = 0;
      this.hidden = false;
      this.fixed = false;     // Fixed vertices are static (unmovable)

      if(style != null) {
          this.style = style;
      }
      else { // Default
          this.style = new foograph.VertexStyle('ellipse', 80, 40, '#ffffff', '#000000', true);
      }
    },


   /**
   * VertexStyle object type for defining vertex style options.
   *
   * @param shape Shape of the vertex ('ellipse' or 'rect')
   * @param width Width in px
   * @param height Height in px
   * @param fillColor The color with which the vertex is drawn (RGB HEX string)
   * @param borderColor The color with which the border of the vertex is drawn (RGB HEX string)
   * @param showLabel Show the vertex label or not
   */
  VertexStyle: function(shape, width, height, fillColor, borderColor, showLabel) {
      this.shape = shape;
      this.width = width;
      this.height = height;
      this.fillColor = fillColor;
      this.borderColor = borderColor;
      this.showLabel = showLabel;
    },

  /**
   * Edge object constructor.
   *
   * @param label Label of this edge
   * @param next Next edge reference
   * @param weight Edge weight
   * @param endVertex Destination Vertex instance
   */
  Edge: function (label, weight, endVertex, style) {
      this.label = label;
      this.weight = weight;
      this.endVertex = endVertex;
      this.style = null;
      this.hidden = false;

      // Curving information
      this.curved = false;
      this.controlX = -1;   // Control coordinates for Bezier curve drawing
      this.controlY = -1;
      this.original = null; // If this is a temporary edge it holds the original edge

      if(style != null) {
        this.style = style;
      }
      else {  // Set to default
        this.style = new foograph.EdgeStyle(2, '#000000', true, false);
      }
    },



  /**
   * EdgeStyle object type for defining vertex style options.
   *
   * @param width Edge line width
   * @param color The color with which the edge is drawn
   * @param showArrow Draw the edge arrow (only if directed)
   * @param showLabel Show the edge label or not
   */
  EdgeStyle: function(width, color, showArrow, showLabel) {
      this.width = width;
      this.color = color;
      this.showArrow = showArrow;
      this.showLabel = showLabel;
    },

  /**
   * This file is part of foograph Javascript graph library.
   *
   * Description: Random vertex layout manager
   */

  /**
   * Class constructor.
   *
   * @param width Layout width
   * @param height Layout height
   */
  RandomVertexLayout: function (width, height) {
      this.width = width;
      this.height = height;
    },


  /**
   * This file is part of foograph Javascript graph library.
   *
   * Description: Fruchterman-Reingold force-directed vertex
   *              layout manager
   */

  /**
   * Class constructor.
   *
   * @param width Layout width
   * @param height Layout height
   * @param iterations Number of iterations -
   * with more iterations it is more likely the layout has converged into a static equilibrium.
   */
  ForceDirectedVertexLayout: function (width, height, iterations, randomize, eps) {
      this.width = width;
      this.height = height;
      this.iterations = iterations;
      this.randomize = randomize;
      this.eps = eps;
      this.callback = function() {};
    },

  A: 1.5, // Fine tune attraction

  R: 0.5  // Fine tune repulsion
};

/**
 * toString overload for easier debugging
 */
foograph.Vertex.prototype.toString = function() {
  return "[v:" + this.label + "] ";
};

/**
 * toString overload for easier debugging
 */
foograph.Edge.prototype.toString = function() {
  return "[e:" + this.endVertex.label + "] ";
};

/**
 * Draw vertex method.
 *
 * @param canvas jsGraphics instance
 */
foograph.Vertex.prototype.draw = function(canvas) {
  var x = this.x;
  var y = this.y;
  var width = this.style.width;
  var height = this.style.height;
  var shape = this.style.shape;

  canvas.setStroke(2);
  canvas.setColor(this.style.fillColor);

  if(shape == 'rect') {
    canvas.fillRect(x, y, width, height);
    canvas.setColor(this.style.borderColor);
    canvas.drawRect(x, y, width, height);
  }
  else { // Default to ellipse
    canvas.fillEllipse(x, y, width, height);
    canvas.setColor(this.style.borderColor);
    canvas.drawEllipse(x, y, width, height);
  }

  if(this.style.showLabel) {
    canvas.drawStringRect(this.label, x, y + height/2 - 7, width, 'center');
  }
};

/**
 * Fits the graph into the bounding box
 *
 * @param width
 * @param height
 * @param preserveAspect
 */
foograph.Graph.prototype.normalize = function(width, height, preserveAspect) {
  for (var i8 in this.vertices) {
    var v = this.vertices[i8];
    v.oldX = v.x;
    v.oldY = v.y;
  }
  var mnx = width  * 0.1;
  var mxx = width  * 0.9;
  var mny = height * 0.1;
  var mxy = height * 0.9;
  if (preserveAspect == null)
    preserveAspect = true;

  var minx = Number.MAX_VALUE;
  var miny = Number.MAX_VALUE;
  var maxx = Number.MIN_VALUE;
  var maxy = Number.MIN_VALUE;

  for (var i7 in this.vertices) {
    var v = this.vertices[i7];
    if (v.x < minx) minx = v.x;
    if (v.y < miny) miny = v.y;
    if (v.x > maxx) maxx = v.x;
    if (v.y > maxy) maxy = v.y;
  }
  var kx = (mxx-mnx) / (maxx - minx);
  var ky = (mxy-mny) / (maxy - miny);

  if (preserveAspect) {
    kx = Math.min(kx, ky);
    ky = Math.min(kx, ky);
  }

  var newMaxx = Number.MIN_VALUE;
  var newMaxy = Number.MIN_VALUE;
  for (var i8 in this.vertices) {
    var v = this.vertices[i8];
    v.x = (v.x - minx) * kx;
    v.y = (v.y - miny) * ky;
    if (v.x > newMaxx) newMaxx = v.x;
    if (v.y > newMaxy) newMaxy = v.y;
  }

  var dx = ( width  - newMaxx ) / 2.0;
  var dy = ( height - newMaxy ) / 2.0;
  for (var i8 in this.vertices) {
    var v = this.vertices[i8];
    v.x += dx;
    v.y += dy;
  }
};

/**
 * Draw edge method. Draws edge "v" --> "this".
 *
 * @param canvas jsGraphics instance
 * @param v Start vertex
 */
foograph.Edge.prototype.draw = function(canvas, v) {
  var x1 = Math.round(v.x + v.style.width/2);
  var y1 = Math.round(v.y + v.style.height/2);
  var x2 = Math.round(this.endVertex.x + this.endVertex.style.width/2);
  var y2 = Math.round(this.endVertex.y + this.endVertex.style.height/2);

  // Control point (needed only for curved edges)
  var x3 = this.controlX;
  var y3 = this.controlY;

  // Arrow tip and angle
  var X_TIP, Y_TIP, ANGLE;

  /* Quadric Bezier curve definition. */
  function Bx(t) { return (1-t)*(1-t)*x1 + 2*(1-t)*t*x3 + t*t*x2; }
  function By(t) { return (1-t)*(1-t)*y1 + 2*(1-t)*t*y3 + t*t*y2; }

  canvas.setStroke(this.style.width);
  canvas.setColor(this.style.color);

  if(this.curved) { // Draw a quadric Bezier curve
    this.curved = false; // Reset
    var t = 0, dt = 1/10;
    var xs = x1, ys = y1, xn, yn;

    while (t < 1-dt) {
      t += dt;
      xn = Bx(t);
      yn = By(t);
      canvas.drawLine(xs, ys, xn, yn);
      xs = xn;
      ys = yn;
    }

    // Set the arrow tip coordinates
    X_TIP = xs;
    Y_TIP = ys;

    // Move the tip to (0,0) and calculate the angle
    // of the arrow head
    ANGLE = angularCoord(Bx(1-2*dt) - X_TIP, By(1-2*dt) - Y_TIP);

  } else {
    canvas.drawLine(x1, y1, x2, y2);

    // Set the arrow tip coordinates
    X_TIP = x2;
    Y_TIP = y2;

    // Move the tip to (0,0) and calculate the angle
    // of the arrow head
    ANGLE = angularCoord(x1 - X_TIP, y1 - Y_TIP);
  }

  if(this.style.showArrow) {
    drawArrow(ANGLE, X_TIP, Y_TIP);
  }

  // TODO
  if(this.style.showLabel) {
  }

  /**
   * Draws an edge arrow.
   * @param phi The angle (in radians) of the arrow in polar coordinates.
   * @param x X coordinate of the arrow tip.
   * @param y Y coordinate of the arrow tip.
   */
  function drawArrow(phi, x, y)
  {
    // Arrow bounding box (in px)
    var H = 50;
    var W = 10;

    // Set cartesian coordinates of the arrow
    var p11 = 0, p12 = 0;
    var p21 = H, p22 = W/2;
    var p31 = H, p32 = -W/2;

    // Convert to polar coordinates
    var r2 = radialCoord(p21, p22);
    var r3 = radialCoord(p31, p32);
    var phi2 = angularCoord(p21, p22);
    var phi3 = angularCoord(p31, p32);

    // Rotate the arrow
    phi2 += phi;
    phi3 += phi;

    // Update cartesian coordinates
    p21 = r2 * Math.cos(phi2);
    p22 = r2 * Math.sin(phi2);
    p31 = r3 * Math.cos(phi3);
    p32 = r3 * Math.sin(phi3);

    // Translate
    p11 += x;
    p12 += y;
    p21 += x;
    p22 += y;
    p31 += x;
    p32 += y;

    // Draw
    canvas.fillPolygon(new Array(p11, p21, p31), new Array(p12, p22, p32));
  }

  /**
   * Get the angular coordinate.
   * @param x X coordinate
   * @param y Y coordinate
   */
   function angularCoord(x, y)
   {
     var phi = 0.0;

     if (x > 0 && y >= 0) {
      phi = Math.atan(y/x);
     }
     if (x > 0 && y < 0) {
       phi = Math.atan(y/x) + 2*Math.PI;
     }
     if (x < 0) {
       phi = Math.atan(y/x) + Math.PI;
     }
     if (x = 0 && y > 0) {
       phi = Math.PI/2;
     }
     if (x = 0 && y < 0) {
       phi = 3*Math.PI/2;
     }

     return phi;
   }

   /**
    * Get the radian coordiante.
    * @param x1
    * @param y1
    * @param x2
    * @param y2
    */
   function radialCoord(x, y)
   {
     return Math.sqrt(x*x + y*y);
   }
};

/**
 * Calculates the coordinates based on pure chance.
 *
 * @param graph A valid graph instance
 */
foograph.RandomVertexLayout.prototype.layout = function(graph) {
  for (var i = 0; i<graph.vertices.length; i++) {
    var v = graph.vertices[i];
    v.x = Math.round(Math.random() * this.width);
    v.y = Math.round(Math.random() * this.height);
  }
};

/**
 * Identifies connected components of a graph and creates "central"
 * vertices for each component. If there is more than one component,
 * all central vertices of individual components are connected to
 * each other to prevent component drift.
 *
 * @param graph A valid graph instance
 * @return A list of component center vertices or null when there
 *         is only one component.
 */
foograph.ForceDirectedVertexLayout.prototype.__identifyComponents = function(graph) {
  var componentCenters = new Array();
  var components = new Array();

  // Depth first search
  function dfs(vertex)
  {
    var stack = new Array();
    var component = new Array();
    var centerVertex = new foograph.Vertex("component_center", -1, -1);
    centerVertex.hidden = true;
    componentCenters.push(centerVertex);
    components.push(component);

    function visitVertex(v)
    {
      component.push(v);
      v.__dfsVisited = true;

      for (var i in v.edges) {
        var e = v.edges[i];
        if (!e.hidden)
          stack.push(e.endVertex);
      }

      for (var i in v.reverseEdges) {
        if (!v.reverseEdges[i].hidden)
          stack.push(v.reverseEdges[i].endVertex);
      }
    }

    visitVertex(vertex);
    while (stack.length > 0) {
      var u = stack.pop();

      if (!u.__dfsVisited && !u.hidden) {
        visitVertex(u);
      }
    }
  }

  // Clear DFS visited flag
  for (var i in graph.vertices) {
    var v = graph.vertices[i];
    v.__dfsVisited = false;
  }

  // Iterate through all vertices starting DFS from each vertex
  // that hasn't been visited yet.
  for (var k in graph.vertices) {
    var v = graph.vertices[k];
    if (!v.__dfsVisited && !v.hidden)
      dfs(v);
  }

  // Interconnect all center vertices
  if (componentCenters.length > 1) {
    for (var i in componentCenters) {
      graph.insertVertex(componentCenters[i]);
    }
    for (var i in components) {
      for (var j in components[i]) {
        // Connect visited vertex to "central" component vertex
        edge = graph.insertEdge("", 1, components[i][j], componentCenters[i]);
        edge.hidden = true;
      }
    }

    for (var i in componentCenters) {
      for (var j in componentCenters) {
        if (i != j) {
          e = graph.insertEdge("", 3, componentCenters[i], componentCenters[j]);
          e.hidden = true;
        }
      }
    }

    return componentCenters;
  }

  return null;
};

/**
 * Calculates the coordinates based on force-directed placement
 * algorithm.
 *
 * @param graph A valid graph instance
 */
foograph.ForceDirectedVertexLayout.prototype.layout = function(graph) {
  this.graph = graph;
  var area = this.width * this.height;
  var k = Math.sqrt(area / graph.vertexCount);

  var t = this.width / 10; // Temperature.
  var dt = t / (this.iterations + 1);

  var eps = this.eps; // Minimum distance between the vertices

  // Attractive and repulsive forces
  function Fa(z) { return foograph.A*z*z/k; }
  function Fr(z) { return foograph.R*k*k/z; }
  function Fw(z) { return 1/z*z; }  // Force emited by the walls

  // Initiate component identification and virtual vertex creation
  // to prevent disconnected graph components from drifting too far apart
  centers = this.__identifyComponents(graph);

  // Assign initial random positions
  if(this.randomize) {
    randomLayout = new foograph.RandomVertexLayout(this.width, this.height);
    randomLayout.layout(graph);
  }

  // Run through some iterations
  for (var q = 0; q < this.iterations; q++) {

    /* Calculate repulsive forces. */
    for (var i1 in graph.vertices) {
      var v = graph.vertices[i1];

      v.dx = 0;
      v.dy = 0;
      // Do not move fixed vertices
      if(!v.fixed) {
        for (var i2 in graph.vertices) {
          var u = graph.vertices[i2];
          if (v != u && !u.fixed) {
            /* Difference vector between the two vertices. */
            var difx = v.x - u.x;
            var dify = v.y - u.y;

            /* Length of the dif vector. */
            var d = Math.max(eps, Math.sqrt(difx*difx + dify*dify));
            var force = Fr(d);
            v.dx = v.dx + (difx/d) * force;
            v.dy = v.dy + (dify/d) * force;
          }
        }
        /* Treat the walls as static objects emiting force Fw. */
        // Calculate the sum of "wall" forces in (v.x, v.y)
        /*
        var x = Math.max(eps, v.x);
        var y = Math.max(eps, v.y);
        var wx = Math.max(eps, this.width - v.x);
        var wy = Math.max(eps, this.height - v.y);   // Gotta love all those NaN's :)
        var Rx = Fw(x) - Fw(wx);
        var Ry = Fw(y) - Fw(wy);

        v.dx = v.dx + Rx;
        v.dy = v.dy + Ry;
        */
      }
    }

    /* Calculate attractive forces. */
    for (var i3 in graph.vertices) {
      var v = graph.vertices[i3];

      // Do not move fixed vertices
      if(!v.fixed) {
        for (var i4 in v.edges) {
          var e = v.edges[i4];
          var u = e.endVertex;
          var difx = v.x - u.x;
          var dify = v.y - u.y;
          var d = Math.max(eps, Math.sqrt(difx*difx + dify*dify));
          var force = Fa(d);

          /* Length of the dif vector. */
          var d = Math.max(eps, Math.sqrt(difx*difx + dify*dify));
          v.dx = v.dx - (difx/d) * force;
          v.dy = v.dy - (dify/d) * force;

          u.dx = u.dx + (difx/d) * force;
          u.dy = u.dy + (dify/d) * force;
        }
      }
    }

    /* Limit the maximum displacement to the temperature t
        and prevent from being displaced outside frame.     */
    for (var i5 in graph.vertices) {
      var v = graph.vertices[i5];
      if(!v.fixed) {
        /* Length of the displacement vector. */
        var d = Math.max(eps, Math.sqrt(v.dx*v.dx + v.dy*v.dy));

        /* Limit to the temperature t. */
        v.x = v.x + (v.dx/d) * Math.min(d, t);
        v.y = v.y + (v.dy/d) * Math.min(d, t);

        /* Stay inside the frame. */
        /*
        borderWidth = this.width / 50;
        if (v.x < borderWidth) {
          v.x = borderWidth;
        } else if (v.x > this.width - borderWidth) {
          v.x = this.width - borderWidth;
        }

        if (v.y < borderWidth) {
          v.y = borderWidth;
        } else if (v.y > this.height - borderWidth) {
          v.y = this.height - borderWidth;
        }
        */
        v.x = Math.round(v.x);
        v.y = Math.round(v.y);
      }
    }

    /* Cool. */
    t -= dt;

    if (q % 10 == 0) {
      this.callback();
    }
  }

  // Remove virtual center vertices
  if (centers) {
    for (var i in centers) {
      graph.removeVertex(centers[i]);
    }
  }

  graph.normalize(this.width, this.height, true);
};

module.exports = foograph;

},{}],2:[function(_dereq_,module,exports){
'use strict';

(function(){

  // registers the extension on a cytoscape lib ref
  var getLayout = _dereq_('./layout');
  var register = function( cytoscape ){
    var layout = getLayout( cytoscape );

    cytoscape('layout', 'spread', layout);
  };

  if( typeof module !== 'undefined' && module.exports ){ // expose as a commonjs module
    module.exports = register;
  }

  if( typeof define !== 'undefined' && define.amd ){ // expose as an amd/requirejs module
    define('cytoscape-spread', function(){
      return register;
    });
  }

  if( typeof cytoscape !== 'undefined' ){ // expose to global cytoscape (i.e. window.cytoscape)
    register( cytoscape );
  }

})();

},{"./layout":3}],3:[function(_dereq_,module,exports){
var Thread;

var foograph = _dereq_('./foograph');
var Voronoi = _dereq_('./rhill-voronoi-core');

/*
 * This layout combines several algorithms:
 *
 * - It generates an initial position of the nodes by using the
 *   Fruchterman-Reingold algorithm (doi:10.1002/spe.4380211102)
 *
 * - Finally it eliminates overlaps by using the method described by
 *   Gansner and North (doi:10.1007/3-540-37623-2_28)
 */

var defaults = {
  animate: true, // whether to show the layout as it's running
  ready: undefined, // Callback on layoutready
  stop: undefined, // Callback on layoutstop
  fit: true, // Reset viewport to fit default simulationBounds
  minDist: 20, // Minimum distance between nodes
  padding: 20, // Padding
  expandingFactor: -1.0, // If the network does not satisfy the minDist
  // criterium then it expands the network of this amount
  // If it is set to -1.0 the amount of expansion is automatically
  // calculated based on the minDist, the aspect ratio and the
  // number of nodes
  maxFruchtermanReingoldIterations: 50, // Maximum number of initial force-directed iterations
  maxExpandIterations: 4, // Maximum number of expanding iterations
  boundingBox: undefined, // Constrain layout bounds; { x1, y1, x2, y2 } or { x1, y1, w, h }
  randomize: false // uses random initial node positions on true
};

function SpreadLayout( options ) {
  var opts = this.options = {};
  for( var i in defaults ){ opts[i] = defaults[i]; }
  for( var i in options ){ opts[i] = options[i]; }
}

SpreadLayout.prototype.run = function() {

  var layout = this;
  var options = this.options;
  var cy = options.cy;

  var bb = options.boundingBox || { x1: 0, y1: 0, w: cy.width(), h: cy.height() };
  if( bb.x2 === undefined ){ bb.x2 = bb.x1 + bb.w; }
  if( bb.w === undefined ){ bb.w = bb.x2 - bb.x1; }
  if( bb.y2 === undefined ){ bb.y2 = bb.y1 + bb.h; }
  if( bb.h === undefined ){ bb.h = bb.y2 - bb.y1; }

  var nodes = cy.nodes();
  var edges = cy.edges();
  var cWidth = cy.width();
  var cHeight = cy.height();
  var simulationBounds = bb;
  var padding = options.padding;
  var simBBFactor = Math.max( 1, Math.log(nodes.length) * 0.8 );

  if( nodes.length < 100 ){
    simBBFactor /= 2;
  }

  layout.trigger( {
    type: 'layoutstart',
    layout: layout
  } );

  var simBB = {
    x1: 0,
    y1: 0,
    x2: cWidth * simBBFactor,
    y2: cHeight * simBBFactor
  };

  if( simulationBounds ) {
    simBB.x1 = simulationBounds.x1;
    simBB.y1 = simulationBounds.y1;
    simBB.x2 = simulationBounds.x2;
    simBB.y2 = simulationBounds.y2;
  }

  simBB.x1 += padding;
  simBB.y1 += padding;
  simBB.x2 -= padding;
  simBB.y2 -= padding;

  var width = simBB.x2 - simBB.x1;
  var height = simBB.y2 - simBB.y1;

  // Get start time
  var startTime = Date.now();

  // layout doesn't work with just 1 node
  if( nodes.size() <= 1 ) {
    nodes.positions( {
      x: Math.round( ( simBB.x1 + simBB.x2 ) / 2 ),
      y: Math.round( ( simBB.y1 + simBB.y2 ) / 2 )
    } );

    if( options.fit ) {
      cy.fit( options.padding );
    }

    // Get end time
    var endTime = Date.now();
    console.info( "Layout on " + nodes.size() + " nodes took " + ( endTime - startTime ) + " ms" );

    layout.one( "layoutready", options.ready );
    layout.trigger( "layoutready" );

    layout.one( "layoutstop", options.stop );
    layout.trigger( "layoutstop" );

    return;
  }

  // First I need to create the data structure to pass to the worker
  var pData = {
    'width': width,
    'height': height,
    'minDist': options.minDist,
    'expFact': options.expandingFactor,
    'expIt': 0,
    'maxExpIt': options.maxExpandIterations,
    'vertices': [],
    'edges': [],
    'startTime': startTime,
    'maxFruchtermanReingoldIterations': options.maxFruchtermanReingoldIterations
  };

  nodes.each(
    function( i, node ) {
      var nodeId = node.id();
      var pos = node.position();

      if( options.randomize ){
        pos = {
          x: Math.round( simBB.x1 + (simBB.x2 - simBB.x1) * Math.random() ),
          y: Math.round( simBB.y1 + (simBB.y2 - simBB.y1) * Math.random() )
        };
      }

      pData[ 'vertices' ].push( {
        id: nodeId,
        x: pos.x,
        y: pos.y
      } );
    } );

  edges.each(
    function() {
      var srcNodeId = this.source().id();
      var tgtNodeId = this.target().id();
      pData[ 'edges' ].push( {
        src: srcNodeId,
        tgt: tgtNodeId
      } );
    } );

  //Decleration
  var t1 = layout.thread;

  // reuse old thread if possible
  if( !t1 || t1.stopped() ){
    t1 = layout.thread = Thread();

    // And to add the required scripts
    //EXTERNAL 1
    t1.require( foograph, 'foograph' );
    //EXTERNAL 2
    t1.require( Voronoi, 'Voronoi' );
  }

  function setPositions( pData ){ //console.log('set posns')
    // First we retrieve the important data
    // var expandIteration = pData[ 'expIt' ];
    var dataVertices = pData[ 'vertices' ];
    var vertices = [];
    for( var i = 0; i < dataVertices.length; ++i ) {
      var dv = dataVertices[ i ];
      vertices[ dv.id ] = {
        x: dv.x,
        y: dv.y
      };
    }
    /*
     * FINALLY:
     *
     * We position the nodes based on the calculation
     */
    nodes.positions(
      function( i, node ) {
        var id = node.id()
        var vertex = vertices[ id ];

        return {
          x: Math.round( simBB.x1 + vertex.x ),
          y: Math.round( simBB.y1 + vertex.y )
        };
      } );

    if( options.fit ) {
      cy.fit( options.padding );
    }

    cy.nodes().rtrigger( "position" );
  }

  var didLayoutReady = false;
  t1.on('message', function(e){
    var pData = e.message; //console.log('message', e)

    if( !options.animate ){
      return;
    }

    setPositions( pData );

    if( !didLayoutReady ){
      layout.trigger( "layoutready" );

      didLayoutReady = true;
    }
  });

  layout.one( "layoutready", options.ready );

  t1.pass( pData ).run( function( pData ) {

    function cellCentroid( cell ) {
      var hes = cell.halfedges;
      var area = 0,
        x = 0,
        y = 0;
      var p1, p2, f;

      for( var i = 0; i < hes.length; ++i ) {
        p1 = hes[ i ].getEndpoint();
        p2 = hes[ i ].getStartpoint();

        area += p1.x * p2.y;
        area -= p1.y * p2.x;

        f = p1.x * p2.y - p2.x * p1.y;
        x += ( p1.x + p2.x ) * f;
        y += ( p1.y + p2.y ) * f;
      }

      area /= 2;
      f = area * 6;
      return {
        x: x / f,
        y: y / f
      };
    }

    function sitesDistance( ls, rs ) {
      var dx = ls.x - rs.x;
      var dy = ls.y - rs.y;
      return Math.sqrt( dx * dx + dy * dy );
    }

    foograph = eval('foograph');
    Voronoi = eval('Voronoi');

    // I need to retrieve the important data
    var lWidth = pData[ 'width' ];
    var lHeight = pData[ 'height' ];
    var lMinDist = pData[ 'minDist' ];
    var lExpFact = pData[ 'expFact' ];
    var lMaxExpIt = pData[ 'maxExpIt' ];
    var lMaxFruchtermanReingoldIterations = pData[ 'maxFruchtermanReingoldIterations' ];

    // Prepare the data to output
    var savePositions = function(){
      pData[ 'width' ] = lWidth;
      pData[ 'height' ] = lHeight;
      pData[ 'expIt' ] = expandIteration;
      pData[ 'expFact' ] = lExpFact;

      pData[ 'vertices' ] = [];
      for( var i = 0; i < fv.length; ++i ) {
        pData[ 'vertices' ].push( {
          id: fv[ i ].label,
          x: fv[ i ].x,
          y: fv[ i ].y
        } );
      }
    };

    var messagePositions = function(){
      broadcast( pData );
    };

    /*
     * FIRST STEP: Application of the Fruchterman-Reingold algorithm
     *
     * We use the version implemented by the foograph library
     *
     * Ref.: https://code.google.com/p/foograph/
     */

    // We need to create an instance of a graph compatible with the library
    var frg = new foograph.Graph( "FRgraph", false );

    var frgNodes = {};

    // Then we have to add the vertices
    var dataVertices = pData[ 'vertices' ];
    for( var ni = 0; ni < dataVertices.length; ++ni ) {
      var id = dataVertices[ ni ][ 'id' ];
      var v = new foograph.Vertex( id, Math.round( Math.random() * lHeight ), Math.round( Math.random() * lHeight ) );
      frgNodes[ id ] = v;
      frg.insertVertex( v );
    }

    var dataEdges = pData[ 'edges' ];
    for( var ei = 0; ei < dataEdges.length; ++ei ) {
      var srcNodeId = dataEdges[ ei ][ 'src' ];
      var tgtNodeId = dataEdges[ ei ][ 'tgt' ];
      frg.insertEdge( "", 1, frgNodes[ srcNodeId ], frgNodes[ tgtNodeId ] );
    }

    var fv = frg.vertices;

    // Then we apply the layout
    var iterations = lMaxFruchtermanReingoldIterations;
    var frLayoutManager = new foograph.ForceDirectedVertexLayout( lWidth, lHeight, iterations, false, lMinDist );

    frLayoutManager.callback = function(){
      savePositions();
      messagePositions();
    };

    frLayoutManager.layout( frg );

    savePositions();
    messagePositions();

    if( lMaxExpIt <= 0 ){
      return pData;
    }

    /*
     * SECOND STEP: Tiding up of the graph.
     *
     * We use the method described by Gansner and North, based on Voronoi
     * diagrams.
     *
     * Ref: doi:10.1007/3-540-37623-2_28
     */

    // We calculate the Voronoi diagram dor the position of the nodes
    var voronoi = new Voronoi();
    var bbox = {
      xl: 0,
      xr: lWidth,
      yt: 0,
      yb: lHeight
    };
    var vSites = [];
    for( var i = 0; i < fv.length; ++i ) {
      vSites[ fv[ i ].label ] = fv[ i ];
    }

    function checkMinDist( ee ) {
      var infractions = 0;
      // Then we check if the minimum distance is satisfied
      for( var eei = 0; eei < ee.length; ++eei ) {
        var e = ee[ eei ];
        if( ( e.lSite != null ) && ( e.rSite != null ) && sitesDistance( e.lSite, e.rSite ) < lMinDist ) {
          ++infractions;
        }
      }
      return infractions;
    }

    var diagram = voronoi.compute( fv, bbox );

    // Then we reposition the nodes at the centroid of their Voronoi cells
    var cells = diagram.cells;
    for( var i = 0; i < cells.length; ++i ) {
      var cell = cells[ i ];
      var site = cell.site;
      var centroid = cellCentroid( cell );
      var currv = vSites[ site.label ];
      currv.x = centroid.x;
      currv.y = centroid.y;
    }

    if( lExpFact < 0.0 ) {
      // Calculates the expanding factor
      lExpFact = Math.max( 0.05, Math.min( 0.10, lMinDist / Math.sqrt( ( lWidth * lHeight ) / fv.length ) * 0.5 ) );
      //console.info("Expanding factor is " + (options.expandingFactor * 100.0) + "%");
    }

    var prevInfractions = checkMinDist( diagram.edges );
    //console.info("Initial infractions " + prevInfractions);

    var bStop = ( prevInfractions <= 0 ) || lMaxExpIt <= 0;

    var voronoiIteration = 0;
    var expandIteration = 0;

    // var initWidth = lWidth;

    while( !bStop ) {
      ++voronoiIteration;
      for( var it = 0; it <= 4; ++it ) {
        voronoi.recycle( diagram );
        diagram = voronoi.compute( fv, bbox );

        // Then we reposition the nodes at the centroid of their Voronoi cells
        // cells = diagram.cells;
        for( var i = 0; i < cells.length; ++i ) {
          var cell = cells[ i ];
          var site = cell.site;
          var centroid = cellCentroid( cell );
          var currv = vSites[ site.label ];
          currv.x = centroid.x;
          currv.y = centroid.y;
        }
      }

      var currInfractions = checkMinDist( diagram.edges );
      //console.info("Current infractions " + currInfractions);

      if( currInfractions <= 0 ) {
        bStop = true;
      } else {
        if( currInfractions >= prevInfractions || voronoiIteration >= 4 ) {
          if( expandIteration >= lMaxExpIt ) {
            bStop = true;
          } else {
            lWidth += lWidth * lExpFact;
            lHeight += lHeight * lExpFact;
            bbox = {
              xl: 0,
              xr: lWidth,
              yt: 0,
              yb: lHeight
            };
            ++expandIteration;
            voronoiIteration = 0;
            //console.info("Expanded to ("+width+","+height+")");
          }
        }
      }
      prevInfractions = currInfractions;

      savePositions();
      messagePositions();
    }

    savePositions();
    return pData;

  } ).then( function( pData ) {
    // var expandIteration = pData[ 'expIt' ];
    var dataVertices = pData[ 'vertices' ];

    setPositions( pData );

    // Get end time
    var startTime = pData[ 'startTime' ];
    var endTime = new Date();
    console.info( "Layout on " + dataVertices.length + " nodes took " + ( endTime - startTime ) + " ms" );

    layout.one( "layoutstop", options.stop );

    if( !options.animate ){
      layout.trigger( "layoutready" );
    }

    layout.trigger( "layoutstop" );

    t1.stop();
  } );


  return this;
}; // run

SpreadLayout.prototype.stop = function(){
  if( this.thread ){
    this.thread.stop();
  }

  this.trigger('layoutstop');
};

SpreadLayout.prototype.destroy = function(){
  if( this.thread ){
    this.thread.stop();
  }
};

module.exports = function get( cytoscape ){
  Thread = cytoscape.Thread;

  return SpreadLayout;
};

},{"./foograph":1,"./rhill-voronoi-core":4}],4:[function(_dereq_,module,exports){
/*!
Copyright (C) 2010-2013 Raymond Hill: https://github.com/gorhill/Javascript-Voronoi
MIT License: See https://github.com/gorhill/Javascript-Voronoi/LICENSE.md
*/
/*
Author: Raymond Hill (rhill@raymondhill.net)
Contributor: Jesse Morgan (morgajel@gmail.com)
File: rhill-voronoi-core.js
Version: 0.98
Date: January 21, 2013
Description: This is my personal Javascript implementation of
Steven Fortune's algorithm to compute Voronoi diagrams.

License: See https://github.com/gorhill/Javascript-Voronoi/LICENSE.md
Credits: See https://github.com/gorhill/Javascript-Voronoi/CREDITS.md
History: See https://github.com/gorhill/Javascript-Voronoi/CHANGELOG.md

## Usage:

  var sites = [{x:300,y:300}, {x:100,y:100}, {x:200,y:500}, {x:250,y:450}, {x:600,y:150}];
  // xl, xr means x left, x right
  // yt, yb means y top, y bottom
  var bbox = {xl:0, xr:800, yt:0, yb:600};
  var voronoi = new Voronoi();
  // pass an object which exhibits xl, xr, yt, yb properties. The bounding
  // box will be used to connect unbound edges, and to close open cells
  result = voronoi.compute(sites, bbox);
  // render, further analyze, etc.

Return value:
  An object with the following properties:

  result.vertices = an array of unordered, unique Voronoi.Vertex objects making
    up the Voronoi diagram.
  result.edges = an array of unordered, unique Voronoi.Edge objects making up
    the Voronoi diagram.
  result.cells = an array of Voronoi.Cell object making up the Voronoi diagram.
    A Cell object might have an empty array of halfedges, meaning no Voronoi
    cell could be computed for a particular cell.
  result.execTime = the time it took to compute the Voronoi diagram, in
    milliseconds.

Voronoi.Vertex object:
  x: The x position of the vertex.
  y: The y position of the vertex.

Voronoi.Edge object:
  lSite: the Voronoi site object at the left of this Voronoi.Edge object.
  rSite: the Voronoi site object at the right of this Voronoi.Edge object (can
    be null).
  va: an object with an 'x' and a 'y' property defining the start point
    (relative to the Voronoi site on the left) of this Voronoi.Edge object.
  vb: an object with an 'x' and a 'y' property defining the end point
    (relative to Voronoi site on the left) of this Voronoi.Edge object.

  For edges which are used to close open cells (using the supplied bounding
  box), the rSite property will be null.

Voronoi.Cell object:
  site: the Voronoi site object associated with the Voronoi cell.
  halfedges: an array of Voronoi.Halfedge objects, ordered counterclockwise,
    defining the polygon for this Voronoi cell.

Voronoi.Halfedge object:
  site: the Voronoi site object owning this Voronoi.Halfedge object.
  edge: a reference to the unique Voronoi.Edge object underlying this
    Voronoi.Halfedge object.
  getStartpoint(): a method returning an object with an 'x' and a 'y' property
    for the start point of this halfedge. Keep in mind halfedges are always
    countercockwise.
  getEndpoint(): a method returning an object with an 'x' and a 'y' property
    for the end point of this halfedge. Keep in mind halfedges are always
    countercockwise.

TODO: Identify opportunities for performance improvement.

TODO: Let the user close the Voronoi cells, do not do it automatically. Not only let
      him close the cells, but also allow him to close more than once using a different
      bounding box for the same Voronoi diagram.
*/

/*global Math */

// ---------------------------------------------------------------------------

function Voronoi() {
    this.vertices = null;
    this.edges = null;
    this.cells = null;
    this.toRecycle = null;
    this.beachsectionJunkyard = [];
    this.circleEventJunkyard = [];
    this.vertexJunkyard = [];
    this.edgeJunkyard = [];
    this.cellJunkyard = [];
    }

// ---------------------------------------------------------------------------

Voronoi.prototype.reset = function() {
    if (!this.beachline) {
        this.beachline = new this.RBTree();
        }
    // Move leftover beachsections to the beachsection junkyard.
    if (this.beachline.root) {
        var beachsection = this.beachline.getFirst(this.beachline.root);
        while (beachsection) {
            this.beachsectionJunkyard.push(beachsection); // mark for reuse
            beachsection = beachsection.rbNext;
            }
        }
    this.beachline.root = null;
    if (!this.circleEvents) {
        this.circleEvents = new this.RBTree();
        }
    this.circleEvents.root = this.firstCircleEvent = null;
    this.vertices = [];
    this.edges = [];
    this.cells = [];
    };

Voronoi.prototype.sqrt = function(n){ return Math.sqrt(n); };
Voronoi.prototype.abs = function(n){ return Math.abs(n); };
Voronoi.prototype.ε = Voronoi.ε = 1e-9;
Voronoi.prototype.invε = Voronoi.invε = 1.0 / Voronoi.ε;
Voronoi.prototype.equalWithEpsilon = function(a,b){return this.abs(a-b)<1e-9;};
Voronoi.prototype.greaterThanWithEpsilon = function(a,b){return a-b>1e-9;};
Voronoi.prototype.greaterThanOrEqualWithEpsilon = function(a,b){return b-a<1e-9;};
Voronoi.prototype.lessThanWithEpsilon = function(a,b){return b-a>1e-9;};
Voronoi.prototype.lessThanOrEqualWithEpsilon = function(a,b){return a-b<1e-9;};

// ---------------------------------------------------------------------------
// Red-Black tree code (based on C version of "rbtree" by Franck Bui-Huu
// https://github.com/fbuihuu/libtree/blob/master/rb.c

Voronoi.prototype.RBTree = function() {
    this.root = null;
    };

Voronoi.prototype.RBTree.prototype.rbInsertSuccessor = function(node, successor) {
    var parent;
    if (node) {
        // >>> rhill 2011-05-27: Performance: cache previous/next nodes
        successor.rbPrevious = node;
        successor.rbNext = node.rbNext;
        if (node.rbNext) {
            node.rbNext.rbPrevious = successor;
            }
        node.rbNext = successor;
        // <<<
        if (node.rbRight) {
            // in-place expansion of node.rbRight.getFirst();
            node = node.rbRight;
            while (node.rbLeft) {node = node.rbLeft;}
            node.rbLeft = successor;
            }
        else {
            node.rbRight = successor;
            }
        parent = node;
        }
    // rhill 2011-06-07: if node is null, successor must be inserted
    // to the left-most part of the tree
    else if (this.root) {
        node = this.getFirst(this.root);
        // >>> Performance: cache previous/next nodes
        successor.rbPrevious = null;
        successor.rbNext = node;
        node.rbPrevious = successor;
        // <<<
        node.rbLeft = successor;
        parent = node;
        }
    else {
        // >>> Performance: cache previous/next nodes
        successor.rbPrevious = successor.rbNext = null;
        // <<<
        this.root = successor;
        parent = null;
        }
    successor.rbLeft = successor.rbRight = null;
    successor.rbParent = parent;
    successor.rbRed = true;
    // Fixup the modified tree by recoloring nodes and performing
    // rotations (2 at most) hence the red-black tree properties are
    // preserved.
    var grandpa, uncle;
    node = successor;
    while (parent && parent.rbRed) {
        grandpa = parent.rbParent;
        if (parent === grandpa.rbLeft) {
            uncle = grandpa.rbRight;
            if (uncle && uncle.rbRed) {
                parent.rbRed = uncle.rbRed = false;
                grandpa.rbRed = true;
                node = grandpa;
                }
            else {
                if (node === parent.rbRight) {
                    this.rbRotateLeft(parent);
                    node = parent;
                    parent = node.rbParent;
                    }
                parent.rbRed = false;
                grandpa.rbRed = true;
                this.rbRotateRight(grandpa);
                }
            }
        else {
            uncle = grandpa.rbLeft;
            if (uncle && uncle.rbRed) {
                parent.rbRed = uncle.rbRed = false;
                grandpa.rbRed = true;
                node = grandpa;
                }
            else {
                if (node === parent.rbLeft) {
                    this.rbRotateRight(parent);
                    node = parent;
                    parent = node.rbParent;
                    }
                parent.rbRed = false;
                grandpa.rbRed = true;
                this.rbRotateLeft(grandpa);
                }
            }
        parent = node.rbParent;
        }
    this.root.rbRed = false;
    };

Voronoi.prototype.RBTree.prototype.rbRemoveNode = function(node) {
    // >>> rhill 2011-05-27: Performance: cache previous/next nodes
    if (node.rbNext) {
        node.rbNext.rbPrevious = node.rbPrevious;
        }
    if (node.rbPrevious) {
        node.rbPrevious.rbNext = node.rbNext;
        }
    node.rbNext = node.rbPrevious = null;
    // <<<
    var parent = node.rbParent,
        left = node.rbLeft,
        right = node.rbRight,
        next;
    if (!left) {
        next = right;
        }
    else if (!right) {
        next = left;
        }
    else {
        next = this.getFirst(right);
        }
    if (parent) {
        if (parent.rbLeft === node) {
            parent.rbLeft = next;
            }
        else {
            parent.rbRight = next;
            }
        }
    else {
        this.root = next;
        }
    // enforce red-black rules
    var isRed;
    if (left && right) {
        isRed = next.rbRed;
        next.rbRed = node.rbRed;
        next.rbLeft = left;
        left.rbParent = next;
        if (next !== right) {
            parent = next.rbParent;
            next.rbParent = node.rbParent;
            node = next.rbRight;
            parent.rbLeft = node;
            next.rbRight = right;
            right.rbParent = next;
            }
        else {
            next.rbParent = parent;
            parent = next;
            node = next.rbRight;
            }
        }
    else {
        isRed = node.rbRed;
        node = next;
        }
    // 'node' is now the sole successor's child and 'parent' its
    // new parent (since the successor can have been moved)
    if (node) {
        node.rbParent = parent;
        }
    // the 'easy' cases
    if (isRed) {return;}
    if (node && node.rbRed) {
        node.rbRed = false;
        return;
        }
    // the other cases
    var sibling;
    do {
        if (node === this.root) {
            break;
            }
        if (node === parent.rbLeft) {
            sibling = parent.rbRight;
            if (sibling.rbRed) {
                sibling.rbRed = false;
                parent.rbRed = true;
                this.rbRotateLeft(parent);
                sibling = parent.rbRight;
                }
            if ((sibling.rbLeft && sibling.rbLeft.rbRed) || (sibling.rbRight && sibling.rbRight.rbRed)) {
                if (!sibling.rbRight || !sibling.rbRight.rbRed) {
                    sibling.rbLeft.rbRed = false;
                    sibling.rbRed = true;
                    this.rbRotateRight(sibling);
                    sibling = parent.rbRight;
                    }
                sibling.rbRed = parent.rbRed;
                parent.rbRed = sibling.rbRight.rbRed = false;
                this.rbRotateLeft(parent);
                node = this.root;
                break;
                }
            }
        else {
            sibling = parent.rbLeft;
            if (sibling.rbRed) {
                sibling.rbRed = false;
                parent.rbRed = true;
                this.rbRotateRight(parent);
                sibling = parent.rbLeft;
                }
            if ((sibling.rbLeft && sibling.rbLeft.rbRed) || (sibling.rbRight && sibling.rbRight.rbRed)) {
                if (!sibling.rbLeft || !sibling.rbLeft.rbRed) {
                    sibling.rbRight.rbRed = false;
                    sibling.rbRed = true;
                    this.rbRotateLeft(sibling);
                    sibling = parent.rbLeft;
                    }
                sibling.rbRed = parent.rbRed;
                parent.rbRed = sibling.rbLeft.rbRed = false;
                this.rbRotateRight(parent);
                node = this.root;
                break;
                }
            }
        sibling.rbRed = true;
        node = parent;
        parent = parent.rbParent;
    } while (!node.rbRed);
    if (node) {node.rbRed = false;}
    };

Voronoi.prototype.RBTree.prototype.rbRotateLeft = function(node) {
    var p = node,
        q = node.rbRight, // can't be null
        parent = p.rbParent;
    if (parent) {
        if (parent.rbLeft === p) {
            parent.rbLeft = q;
            }
        else {
            parent.rbRight = q;
            }
        }
    else {
        this.root = q;
        }
    q.rbParent = parent;
    p.rbParent = q;
    p.rbRight = q.rbLeft;
    if (p.rbRight) {
        p.rbRight.rbParent = p;
        }
    q.rbLeft = p;
    };

Voronoi.prototype.RBTree.prototype.rbRotateRight = function(node) {
    var p = node,
        q = node.rbLeft, // can't be null
        parent = p.rbParent;
    if (parent) {
        if (parent.rbLeft === p) {
            parent.rbLeft = q;
            }
        else {
            parent.rbRight = q;
            }
        }
    else {
        this.root = q;
        }
    q.rbParent = parent;
    p.rbParent = q;
    p.rbLeft = q.rbRight;
    if (p.rbLeft) {
        p.rbLeft.rbParent = p;
        }
    q.rbRight = p;
    };

Voronoi.prototype.RBTree.prototype.getFirst = function(node) {
    while (node.rbLeft) {
        node = node.rbLeft;
        }
    return node;
    };

Voronoi.prototype.RBTree.prototype.getLast = function(node) {
    while (node.rbRight) {
        node = node.rbRight;
        }
    return node;
    };

// ---------------------------------------------------------------------------
// Diagram methods

Voronoi.prototype.Diagram = function(site) {
    this.site = site;
    };

// ---------------------------------------------------------------------------
// Cell methods

Voronoi.prototype.Cell = function(site) {
    this.site = site;
    this.halfedges = [];
    this.closeMe = false;
    };

Voronoi.prototype.Cell.prototype.init = function(site) {
    this.site = site;
    this.halfedges = [];
    this.closeMe = false;
    return this;
    };

Voronoi.prototype.createCell = function(site) {
    var cell = this.cellJunkyard.pop();
    if ( cell ) {
        return cell.init(site);
        }
    return new this.Cell(site);
    };

Voronoi.prototype.Cell.prototype.prepareHalfedges = function() {
    var halfedges = this.halfedges,
        iHalfedge = halfedges.length,
        edge;
    // get rid of unused halfedges
    // rhill 2011-05-27: Keep it simple, no point here in trying
    // to be fancy: dangling edges are a typically a minority.
    while (iHalfedge--) {
        edge = halfedges[iHalfedge].edge;
        if (!edge.vb || !edge.va) {
            halfedges.splice(iHalfedge,1);
            }
        }

    // rhill 2011-05-26: I tried to use a binary search at insertion
    // time to keep the array sorted on-the-fly (in Cell.addHalfedge()).
    // There was no real benefits in doing so, performance on
    // Firefox 3.6 was improved marginally, while performance on
    // Opera 11 was penalized marginally.
    halfedges.sort(function(a,b){return b.angle-a.angle;});
    return halfedges.length;
    };

// Return a list of the neighbor Ids
Voronoi.prototype.Cell.prototype.getNeighborIds = function() {
    var neighbors = [],
        iHalfedge = this.halfedges.length,
        edge;
    while (iHalfedge--){
        edge = this.halfedges[iHalfedge].edge;
        if (edge.lSite !== null && edge.lSite.voronoiId != this.site.voronoiId) {
            neighbors.push(edge.lSite.voronoiId);
            }
        else if (edge.rSite !== null && edge.rSite.voronoiId != this.site.voronoiId){
            neighbors.push(edge.rSite.voronoiId);
            }
        }
    return neighbors;
    };

// Compute bounding box
//
Voronoi.prototype.Cell.prototype.getBbox = function() {
    var halfedges = this.halfedges,
        iHalfedge = halfedges.length,
        xmin = Infinity,
        ymin = Infinity,
        xmax = -Infinity,
        ymax = -Infinity,
        v, vx, vy;
    while (iHalfedge--) {
        v = halfedges[iHalfedge].getStartpoint();
        vx = v.x;
        vy = v.y;
        if (vx < xmin) {xmin = vx;}
        if (vy < ymin) {ymin = vy;}
        if (vx > xmax) {xmax = vx;}
        if (vy > ymax) {ymax = vy;}
        // we dont need to take into account end point,
        // since each end point matches a start point
        }
    return {
        x: xmin,
        y: ymin,
        width: xmax-xmin,
        height: ymax-ymin
        };
    };

// Return whether a point is inside, on, or outside the cell:
//   -1: point is outside the perimeter of the cell
//    0: point is on the perimeter of the cell
//    1: point is inside the perimeter of the cell
//
Voronoi.prototype.Cell.prototype.pointIntersection = function(x, y) {
    // Check if point in polygon. Since all polygons of a Voronoi
    // diagram are convex, then:
    // http://paulbourke.net/geometry/polygonmesh/
    // Solution 3 (2D):
    //   "If the polygon is convex then one can consider the polygon
    //   "as a 'path' from the first vertex. A point is on the interior
    //   "of this polygons if it is always on the same side of all the
    //   "line segments making up the path. ...
    //   "(y - y0) (x1 - x0) - (x - x0) (y1 - y0)
    //   "if it is less than 0 then P is to the right of the line segment,
    //   "if greater than 0 it is to the left, if equal to 0 then it lies
    //   "on the line segment"
    var halfedges = this.halfedges,
        iHalfedge = halfedges.length,
        halfedge,
        p0, p1, r;
    while (iHalfedge--) {
        halfedge = halfedges[iHalfedge];
        p0 = halfedge.getStartpoint();
        p1 = halfedge.getEndpoint();
        r = (y-p0.y)*(p1.x-p0.x)-(x-p0.x)*(p1.y-p0.y);
        if (!r) {
            return 0;
            }
        if (r > 0) {
            return -1;
            }
        }
    return 1;
    };

// ---------------------------------------------------------------------------
// Edge methods
//

Voronoi.prototype.Vertex = function(x, y) {
    this.x = x;
    this.y = y;
    };

Voronoi.prototype.Edge = function(lSite, rSite) {
    this.lSite = lSite;
    this.rSite = rSite;
    this.va = this.vb = null;
    };

Voronoi.prototype.Halfedge = function(edge, lSite, rSite) {
    this.site = lSite;
    this.edge = edge;
    // 'angle' is a value to be used for properly sorting the
    // halfsegments counterclockwise. By convention, we will
    // use the angle of the line defined by the 'site to the left'
    // to the 'site to the right'.
    // However, border edges have no 'site to the right': thus we
    // use the angle of line perpendicular to the halfsegment (the
    // edge should have both end points defined in such case.)
    if (rSite) {
        this.angle = Math.atan2(rSite.y-lSite.y, rSite.x-lSite.x);
        }
    else {
        var va = edge.va,
            vb = edge.vb;
        // rhill 2011-05-31: used to call getStartpoint()/getEndpoint(),
        // but for performance purpose, these are expanded in place here.
        this.angle = edge.lSite === lSite ?
            Math.atan2(vb.x-va.x, va.y-vb.y) :
            Math.atan2(va.x-vb.x, vb.y-va.y);
        }
    };

Voronoi.prototype.createHalfedge = function(edge, lSite, rSite) {
    return new this.Halfedge(edge, lSite, rSite);
    };

Voronoi.prototype.Halfedge.prototype.getStartpoint = function() {
    return this.edge.lSite === this.site ? this.edge.va : this.edge.vb;
    };

Voronoi.prototype.Halfedge.prototype.getEndpoint = function() {
    return this.edge.lSite === this.site ? this.edge.vb : this.edge.va;
    };



// this create and add a vertex to the internal collection

Voronoi.prototype.createVertex = function(x, y) {
    var v = this.vertexJunkyard.pop();
    if ( !v ) {
        v = new this.Vertex(x, y);
        }
    else {
        v.x = x;
        v.y = y;
        }
    this.vertices.push(v);
    return v;
    };

// this create and add an edge to internal collection, and also create
// two halfedges which are added to each site's counterclockwise array
// of halfedges.

Voronoi.prototype.createEdge = function(lSite, rSite, va, vb) {
    var edge = this.edgeJunkyard.pop();
    if ( !edge ) {
        edge = new this.Edge(lSite, rSite);
        }
    else {
        edge.lSite = lSite;
        edge.rSite = rSite;
        edge.va = edge.vb = null;
        }

    this.edges.push(edge);
    if (va) {
        this.setEdgeStartpoint(edge, lSite, rSite, va);
        }
    if (vb) {
        this.setEdgeEndpoint(edge, lSite, rSite, vb);
        }
    this.cells[lSite.voronoiId].halfedges.push(this.createHalfedge(edge, lSite, rSite));
    this.cells[rSite.voronoiId].halfedges.push(this.createHalfedge(edge, rSite, lSite));
    return edge;
    };

Voronoi.prototype.createBorderEdge = function(lSite, va, vb) {
    var edge = this.edgeJunkyard.pop();
    if ( !edge ) {
        edge = new this.Edge(lSite, null);
        }
    else {
        edge.lSite = lSite;
        edge.rSite = null;
        }
    edge.va = va;
    edge.vb = vb;
    this.edges.push(edge);
    return edge;
    };

Voronoi.prototype.setEdgeStartpoint = function(edge, lSite, rSite, vertex) {
    if (!edge.va && !edge.vb) {
        edge.va = vertex;
        edge.lSite = lSite;
        edge.rSite = rSite;
        }
    else if (edge.lSite === rSite) {
        edge.vb = vertex;
        }
    else {
        edge.va = vertex;
        }
    };

Voronoi.prototype.setEdgeEndpoint = function(edge, lSite, rSite, vertex) {
    this.setEdgeStartpoint(edge, rSite, lSite, vertex);
    };

// ---------------------------------------------------------------------------
// Beachline methods

// rhill 2011-06-07: For some reasons, performance suffers significantly
// when instanciating a literal object instead of an empty ctor
Voronoi.prototype.Beachsection = function() {
    };

// rhill 2011-06-02: A lot of Beachsection instanciations
// occur during the computation of the Voronoi diagram,
// somewhere between the number of sites and twice the
// number of sites, while the number of Beachsections on the
// beachline at any given time is comparatively low. For this
// reason, we reuse already created Beachsections, in order
// to avoid new memory allocation. This resulted in a measurable
// performance gain.

Voronoi.prototype.createBeachsection = function(site) {
    var beachsection = this.beachsectionJunkyard.pop();
    if (!beachsection) {
        beachsection = new this.Beachsection();
        }
    beachsection.site = site;
    return beachsection;
    };

// calculate the left break point of a particular beach section,
// given a particular sweep line
Voronoi.prototype.leftBreakPoint = function(arc, directrix) {
    // http://en.wikipedia.org/wiki/Parabola
    // http://en.wikipedia.org/wiki/Quadratic_equation
    // h1 = x1,
    // k1 = (y1+directrix)/2,
    // h2 = x2,
    // k2 = (y2+directrix)/2,
    // p1 = k1-directrix,
    // a1 = 1/(4*p1),
    // b1 = -h1/(2*p1),
    // c1 = h1*h1/(4*p1)+k1,
    // p2 = k2-directrix,
    // a2 = 1/(4*p2),
    // b2 = -h2/(2*p2),
    // c2 = h2*h2/(4*p2)+k2,
    // x = (-(b2-b1) + Math.sqrt((b2-b1)*(b2-b1) - 4*(a2-a1)*(c2-c1))) / (2*(a2-a1))
    // When x1 become the x-origin:
    // h1 = 0,
    // k1 = (y1+directrix)/2,
    // h2 = x2-x1,
    // k2 = (y2+directrix)/2,
    // p1 = k1-directrix,
    // a1 = 1/(4*p1),
    // b1 = 0,
    // c1 = k1,
    // p2 = k2-directrix,
    // a2 = 1/(4*p2),
    // b2 = -h2/(2*p2),
    // c2 = h2*h2/(4*p2)+k2,
    // x = (-b2 + Math.sqrt(b2*b2 - 4*(a2-a1)*(c2-k1))) / (2*(a2-a1)) + x1

    // change code below at your own risk: care has been taken to
    // reduce errors due to computers' finite arithmetic precision.
    // Maybe can still be improved, will see if any more of this
    // kind of errors pop up again.
    var site = arc.site,
        rfocx = site.x,
        rfocy = site.y,
        pby2 = rfocy-directrix;
    // parabola in degenerate case where focus is on directrix
    if (!pby2) {
        return rfocx;
        }
    var lArc = arc.rbPrevious;
    if (!lArc) {
        return -Infinity;
        }
    site = lArc.site;
    var lfocx = site.x,
        lfocy = site.y,
        plby2 = lfocy-directrix;
    // parabola in degenerate case where focus is on directrix
    if (!plby2) {
        return lfocx;
        }
    var hl = lfocx-rfocx,
        aby2 = 1/pby2-1/plby2,
        b = hl/plby2;
    if (aby2) {
        return (-b+this.sqrt(b*b-2*aby2*(hl*hl/(-2*plby2)-lfocy+plby2/2+rfocy-pby2/2)))/aby2+rfocx;
        }
    // both parabolas have same distance to directrix, thus break point is midway
    return (rfocx+lfocx)/2;
    };

// calculate the right break point of a particular beach section,
// given a particular directrix
Voronoi.prototype.rightBreakPoint = function(arc, directrix) {
    var rArc = arc.rbNext;
    if (rArc) {
        return this.leftBreakPoint(rArc, directrix);
        }
    var site = arc.site;
    return site.y === directrix ? site.x : Infinity;
    };

Voronoi.prototype.detachBeachsection = function(beachsection) {
    this.detachCircleEvent(beachsection); // detach potentially attached circle event
    this.beachline.rbRemoveNode(beachsection); // remove from RB-tree
    this.beachsectionJunkyard.push(beachsection); // mark for reuse
    };

Voronoi.prototype.removeBeachsection = function(beachsection) {
    var circle = beachsection.circleEvent,
        x = circle.x,
        y = circle.ycenter,
        vertex = this.createVertex(x, y),
        previous = beachsection.rbPrevious,
        next = beachsection.rbNext,
        disappearingTransitions = [beachsection],
        abs_fn = Math.abs;

    // remove collapsed beachsection from beachline
    this.detachBeachsection(beachsection);

    // there could be more than one empty arc at the deletion point, this
    // happens when more than two edges are linked by the same vertex,
    // so we will collect all those edges by looking up both sides of
    // the deletion point.
    // by the way, there is *always* a predecessor/successor to any collapsed
    // beach section, it's just impossible to have a collapsing first/last
    // beach sections on the beachline, since they obviously are unconstrained
    // on their left/right side.

    // look left
    var lArc = previous;
    while (lArc.circleEvent && abs_fn(x-lArc.circleEvent.x)<1e-9 && abs_fn(y-lArc.circleEvent.ycenter)<1e-9) {
        previous = lArc.rbPrevious;
        disappearingTransitions.unshift(lArc);
        this.detachBeachsection(lArc); // mark for reuse
        lArc = previous;
        }
    // even though it is not disappearing, I will also add the beach section
    // immediately to the left of the left-most collapsed beach section, for
    // convenience, since we need to refer to it later as this beach section
    // is the 'left' site of an edge for which a start point is set.
    disappearingTransitions.unshift(lArc);
    this.detachCircleEvent(lArc);

    // look right
    var rArc = next;
    while (rArc.circleEvent && abs_fn(x-rArc.circleEvent.x)<1e-9 && abs_fn(y-rArc.circleEvent.ycenter)<1e-9) {
        next = rArc.rbNext;
        disappearingTransitions.push(rArc);
        this.detachBeachsection(rArc); // mark for reuse
        rArc = next;
        }
    // we also have to add the beach section immediately to the right of the
    // right-most collapsed beach section, since there is also a disappearing
    // transition representing an edge's start point on its left.
    disappearingTransitions.push(rArc);
    this.detachCircleEvent(rArc);

    // walk through all the disappearing transitions between beach sections and
    // set the start point of their (implied) edge.
    var nArcs = disappearingTransitions.length,
        iArc;
    for (iArc=1; iArc<nArcs; iArc++) {
        rArc = disappearingTransitions[iArc];
        lArc = disappearingTransitions[iArc-1];
        this.setEdgeStartpoint(rArc.edge, lArc.site, rArc.site, vertex);
        }

    // create a new edge as we have now a new transition between
    // two beach sections which were previously not adjacent.
    // since this edge appears as a new vertex is defined, the vertex
    // actually define an end point of the edge (relative to the site
    // on the left)
    lArc = disappearingTransitions[0];
    rArc = disappearingTransitions[nArcs-1];
    rArc.edge = this.createEdge(lArc.site, rArc.site, undefined, vertex);

    // create circle events if any for beach sections left in the beachline
    // adjacent to collapsed sections
    this.attachCircleEvent(lArc);
    this.attachCircleEvent(rArc);
    };

Voronoi.prototype.addBeachsection = function(site) {
    var x = site.x,
        directrix = site.y;

    // find the left and right beach sections which will surround the newly
    // created beach section.
    // rhill 2011-06-01: This loop is one of the most often executed,
    // hence we expand in-place the comparison-against-epsilon calls.
    var lArc, rArc,
        dxl, dxr,
        node = this.beachline.root;

    while (node) {
        dxl = this.leftBreakPoint(node,directrix)-x;
        // x lessThanWithEpsilon xl => falls somewhere before the left edge of the beachsection
        if (dxl > 1e-9) {
            // this case should never happen
            // if (!node.rbLeft) {
            //    rArc = node.rbLeft;
            //    break;
            //    }
            node = node.rbLeft;
            }
        else {
            dxr = x-this.rightBreakPoint(node,directrix);
            // x greaterThanWithEpsilon xr => falls somewhere after the right edge of the beachsection
            if (dxr > 1e-9) {
                if (!node.rbRight) {
                    lArc = node;
                    break;
                    }
                node = node.rbRight;
                }
            else {
                // x equalWithEpsilon xl => falls exactly on the left edge of the beachsection
                if (dxl > -1e-9) {
                    lArc = node.rbPrevious;
                    rArc = node;
                    }
                // x equalWithEpsilon xr => falls exactly on the right edge of the beachsection
                else if (dxr > -1e-9) {
                    lArc = node;
                    rArc = node.rbNext;
                    }
                // falls exactly somewhere in the middle of the beachsection
                else {
                    lArc = rArc = node;
                    }
                break;
                }
            }
        }
    // at this point, keep in mind that lArc and/or rArc could be
    // undefined or null.

    // create a new beach section object for the site and add it to RB-tree
    var newArc = this.createBeachsection(site);
    this.beachline.rbInsertSuccessor(lArc, newArc);

    // cases:
    //

    // [null,null]
    // least likely case: new beach section is the first beach section on the
    // beachline.
    // This case means:
    //   no new transition appears
    //   no collapsing beach section
    //   new beachsection become root of the RB-tree
    if (!lArc && !rArc) {
        return;
        }

    // [lArc,rArc] where lArc == rArc
    // most likely case: new beach section split an existing beach
    // section.
    // This case means:
    //   one new transition appears
    //   the left and right beach section might be collapsing as a result
    //   two new nodes added to the RB-tree
    if (lArc === rArc) {
        // invalidate circle event of split beach section
        this.detachCircleEvent(lArc);

        // split the beach section into two separate beach sections
        rArc = this.createBeachsection(lArc.site);
        this.beachline.rbInsertSuccessor(newArc, rArc);

        // since we have a new transition between two beach sections,
        // a new edge is born
        newArc.edge = rArc.edge = this.createEdge(lArc.site, newArc.site);

        // check whether the left and right beach sections are collapsing
        // and if so create circle events, to be notified when the point of
        // collapse is reached.
        this.attachCircleEvent(lArc);
        this.attachCircleEvent(rArc);
        return;
        }

    // [lArc,null]
    // even less likely case: new beach section is the *last* beach section
    // on the beachline -- this can happen *only* if *all* the previous beach
    // sections currently on the beachline share the same y value as
    // the new beach section.
    // This case means:
    //   one new transition appears
    //   no collapsing beach section as a result
    //   new beach section become right-most node of the RB-tree
    if (lArc && !rArc) {
        newArc.edge = this.createEdge(lArc.site,newArc.site);
        return;
        }

    // [null,rArc]
    // impossible case: because sites are strictly processed from top to bottom,
    // and left to right, which guarantees that there will always be a beach section
    // on the left -- except of course when there are no beach section at all on
    // the beach line, which case was handled above.
    // rhill 2011-06-02: No point testing in non-debug version
    //if (!lArc && rArc) {
    //    throw "Voronoi.addBeachsection(): What is this I don't even";
    //    }

    // [lArc,rArc] where lArc != rArc
    // somewhat less likely case: new beach section falls *exactly* in between two
    // existing beach sections
    // This case means:
    //   one transition disappears
    //   two new transitions appear
    //   the left and right beach section might be collapsing as a result
    //   only one new node added to the RB-tree
    if (lArc !== rArc) {
        // invalidate circle events of left and right sites
        this.detachCircleEvent(lArc);
        this.detachCircleEvent(rArc);

        // an existing transition disappears, meaning a vertex is defined at
        // the disappearance point.
        // since the disappearance is caused by the new beachsection, the
        // vertex is at the center of the circumscribed circle of the left,
        // new and right beachsections.
        // http://mathforum.org/library/drmath/view/55002.html
        // Except that I bring the origin at A to simplify
        // calculation
        var lSite = lArc.site,
            ax = lSite.x,
            ay = lSite.y,
            bx=site.x-ax,
            by=site.y-ay,
            rSite = rArc.site,
            cx=rSite.x-ax,
            cy=rSite.y-ay,
            d=2*(bx*cy-by*cx),
            hb=bx*bx+by*by,
            hc=cx*cx+cy*cy,
            vertex = this.createVertex((cy*hb-by*hc)/d+ax, (bx*hc-cx*hb)/d+ay);

        // one transition disappear
        this.setEdgeStartpoint(rArc.edge, lSite, rSite, vertex);

        // two new transitions appear at the new vertex location
        newArc.edge = this.createEdge(lSite, site, undefined, vertex);
        rArc.edge = this.createEdge(site, rSite, undefined, vertex);

        // check whether the left and right beach sections are collapsing
        // and if so create circle events, to handle the point of collapse.
        this.attachCircleEvent(lArc);
        this.attachCircleEvent(rArc);
        return;
        }
    };

// ---------------------------------------------------------------------------
// Circle event methods

// rhill 2011-06-07: For some reasons, performance suffers significantly
// when instanciating a literal object instead of an empty ctor
Voronoi.prototype.CircleEvent = function() {
    // rhill 2013-10-12: it helps to state exactly what we are at ctor time.
    this.arc = null;
    this.rbLeft = null;
    this.rbNext = null;
    this.rbParent = null;
    this.rbPrevious = null;
    this.rbRed = false;
    this.rbRight = null;
    this.site = null;
    this.x = this.y = this.ycenter = 0;
    };

Voronoi.prototype.attachCircleEvent = function(arc) {
    var lArc = arc.rbPrevious,
        rArc = arc.rbNext;
    if (!lArc || !rArc) {return;} // does that ever happen?
    var lSite = lArc.site,
        cSite = arc.site,
        rSite = rArc.site;

    // If site of left beachsection is same as site of
    // right beachsection, there can't be convergence
    if (lSite===rSite) {return;}

    // Find the circumscribed circle for the three sites associated
    // with the beachsection triplet.
    // rhill 2011-05-26: It is more efficient to calculate in-place
    // rather than getting the resulting circumscribed circle from an
    // object returned by calling Voronoi.circumcircle()
    // http://mathforum.org/library/drmath/view/55002.html
    // Except that I bring the origin at cSite to simplify calculations.
    // The bottom-most part of the circumcircle is our Fortune 'circle
    // event', and its center is a vertex potentially part of the final
    // Voronoi diagram.
    var bx = cSite.x,
        by = cSite.y,
        ax = lSite.x-bx,
        ay = lSite.y-by,
        cx = rSite.x-bx,
        cy = rSite.y-by;

    // If points l->c->r are clockwise, then center beach section does not
    // collapse, hence it can't end up as a vertex (we reuse 'd' here, which
    // sign is reverse of the orientation, hence we reverse the test.
    // http://en.wikipedia.org/wiki/Curve_orientation#Orientation_of_a_simple_polygon
    // rhill 2011-05-21: Nasty finite precision error which caused circumcircle() to
    // return infinites: 1e-12 seems to fix the problem.
    var d = 2*(ax*cy-ay*cx);
    if (d >= -2e-12){return;}

    var ha = ax*ax+ay*ay,
        hc = cx*cx+cy*cy,
        x = (cy*ha-ay*hc)/d,
        y = (ax*hc-cx*ha)/d,
        ycenter = y+by;

    // Important: ybottom should always be under or at sweep, so no need
    // to waste CPU cycles by checking

    // recycle circle event object if possible
    var circleEvent = this.circleEventJunkyard.pop();
    if (!circleEvent) {
        circleEvent = new this.CircleEvent();
        }
    circleEvent.arc = arc;
    circleEvent.site = cSite;
    circleEvent.x = x+bx;
    circleEvent.y = ycenter+this.sqrt(x*x+y*y); // y bottom
    circleEvent.ycenter = ycenter;
    arc.circleEvent = circleEvent;

    // find insertion point in RB-tree: circle events are ordered from
    // smallest to largest
    var predecessor = null,
        node = this.circleEvents.root;
    while (node) {
        if (circleEvent.y < node.y || (circleEvent.y === node.y && circleEvent.x <= node.x)) {
            if (node.rbLeft) {
                node = node.rbLeft;
                }
            else {
                predecessor = node.rbPrevious;
                break;
                }
            }
        else {
            if (node.rbRight) {
                node = node.rbRight;
                }
            else {
                predecessor = node;
                break;
                }
            }
        }
    this.circleEvents.rbInsertSuccessor(predecessor, circleEvent);
    if (!predecessor) {
        this.firstCircleEvent = circleEvent;
        }
    };

Voronoi.prototype.detachCircleEvent = function(arc) {
    var circleEvent = arc.circleEvent;
    if (circleEvent) {
        if (!circleEvent.rbPrevious) {
            this.firstCircleEvent = circleEvent.rbNext;
            }
        this.circleEvents.rbRemoveNode(circleEvent); // remove from RB-tree
        this.circleEventJunkyard.push(circleEvent);
        arc.circleEvent = null;
        }
    };

// ---------------------------------------------------------------------------
// Diagram completion methods

// connect dangling edges (not if a cursory test tells us
// it is not going to be visible.
// return value:
//   false: the dangling endpoint couldn't be connected
//   true: the dangling endpoint could be connected
Voronoi.prototype.connectEdge = function(edge, bbox) {
    // skip if end point already connected
    var vb = edge.vb;
    if (!!vb) {return true;}

    // make local copy for performance purpose
    var va = edge.va,
        xl = bbox.xl,
        xr = bbox.xr,
        yt = bbox.yt,
        yb = bbox.yb,
        lSite = edge.lSite,
        rSite = edge.rSite,
        lx = lSite.x,
        ly = lSite.y,
        rx = rSite.x,
        ry = rSite.y,
        fx = (lx+rx)/2,
        fy = (ly+ry)/2,
        fm, fb;

    // if we reach here, this means cells which use this edge will need
    // to be closed, whether because the edge was removed, or because it
    // was connected to the bounding box.
    this.cells[lSite.voronoiId].closeMe = true;
    this.cells[rSite.voronoiId].closeMe = true;

    // get the line equation of the bisector if line is not vertical
    if (ry !== ly) {
        fm = (lx-rx)/(ry-ly);
        fb = fy-fm*fx;
        }

    // remember, direction of line (relative to left site):
    // upward: left.x < right.x
    // downward: left.x > right.x
    // horizontal: left.x == right.x
    // upward: left.x < right.x
    // rightward: left.y < right.y
    // leftward: left.y > right.y
    // vertical: left.y == right.y

    // depending on the direction, find the best side of the
    // bounding box to use to determine a reasonable start point

    // rhill 2013-12-02:
    // While at it, since we have the values which define the line,
    // clip the end of va if it is outside the bbox.
    // https://github.com/gorhill/Javascript-Voronoi/issues/15
    // TODO: Do all the clipping here rather than rely on Liang-Barsky
    // which does not do well sometimes due to loss of arithmetic
    // precision. The code here doesn't degrade if one of the vertex is
    // at a huge distance.

    // special case: vertical line
    if (fm === undefined) {
        // doesn't intersect with viewport
        if (fx < xl || fx >= xr) {return false;}
        // downward
        if (lx > rx) {
            if (!va || va.y < yt) {
                va = this.createVertex(fx, yt);
                }
            else if (va.y >= yb) {
                return false;
                }
            vb = this.createVertex(fx, yb);
            }
        // upward
        else {
            if (!va || va.y > yb) {
                va = this.createVertex(fx, yb);
                }
            else if (va.y < yt) {
                return false;
                }
            vb = this.createVertex(fx, yt);
            }
        }
    // closer to vertical than horizontal, connect start point to the
    // top or bottom side of the bounding box
    else if (fm < -1 || fm > 1) {
        // downward
        if (lx > rx) {
            if (!va || va.y < yt) {
                va = this.createVertex((yt-fb)/fm, yt);
                }
            else if (va.y >= yb) {
                return false;
                }
            vb = this.createVertex((yb-fb)/fm, yb);
            }
        // upward
        else {
            if (!va || va.y > yb) {
                va = this.createVertex((yb-fb)/fm, yb);
                }
            else if (va.y < yt) {
                return false;
                }
            vb = this.createVertex((yt-fb)/fm, yt);
            }
        }
    // closer to horizontal than vertical, connect start point to the
    // left or right side of the bounding box
    else {
        // rightward
        if (ly < ry) {
            if (!va || va.x < xl) {
                va = this.createVertex(xl, fm*xl+fb);
                }
            else if (va.x >= xr) {
                return false;
                }
            vb = this.createVertex(xr, fm*xr+fb);
            }
        // leftward
        else {
            if (!va || va.x > xr) {
                va = this.createVertex(xr, fm*xr+fb);
                }
            else if (va.x < xl) {
                return false;
                }
            vb = this.createVertex(xl, fm*xl+fb);
            }
        }
    edge.va = va;
    edge.vb = vb;

    return true;
    };

// line-clipping code taken from:
//   Liang-Barsky function by Daniel White
//   http://www.skytopia.com/project/articles/compsci/clipping.html
// Thanks!
// A bit modified to minimize code paths
Voronoi.prototype.clipEdge = function(edge, bbox) {
    var ax = edge.va.x,
        ay = edge.va.y,
        bx = edge.vb.x,
        by = edge.vb.y,
        t0 = 0,
        t1 = 1,
        dx = bx-ax,
        dy = by-ay;
    // left
    var q = ax-bbox.xl;
    if (dx===0 && q<0) {return false;}
    var r = -q/dx;
    if (dx<0) {
        if (r<t0) {return false;}
        if (r<t1) {t1=r;}
        }
    else if (dx>0) {
        if (r>t1) {return false;}
        if (r>t0) {t0=r;}
        }
    // right
    q = bbox.xr-ax;
    if (dx===0 && q<0) {return false;}
    r = q/dx;
    if (dx<0) {
        if (r>t1) {return false;}
        if (r>t0) {t0=r;}
        }
    else if (dx>0) {
        if (r<t0) {return false;}
        if (r<t1) {t1=r;}
        }
    // top
    q = ay-bbox.yt;
    if (dy===0 && q<0) {return false;}
    r = -q/dy;
    if (dy<0) {
        if (r<t0) {return false;}
        if (r<t1) {t1=r;}
        }
    else if (dy>0) {
        if (r>t1) {return false;}
        if (r>t0) {t0=r;}
        }
    // bottom
    q = bbox.yb-ay;
    if (dy===0 && q<0) {return false;}
    r = q/dy;
    if (dy<0) {
        if (r>t1) {return false;}
        if (r>t0) {t0=r;}
        }
    else if (dy>0) {
        if (r<t0) {return false;}
        if (r<t1) {t1=r;}
        }

    // if we reach this point, Voronoi edge is within bbox

    // if t0 > 0, va needs to change
    // rhill 2011-06-03: we need to create a new vertex rather
    // than modifying the existing one, since the existing
    // one is likely shared with at least another edge
    if (t0 > 0) {
        edge.va = this.createVertex(ax+t0*dx, ay+t0*dy);
        }

    // if t1 < 1, vb needs to change
    // rhill 2011-06-03: we need to create a new vertex rather
    // than modifying the existing one, since the existing
    // one is likely shared with at least another edge
    if (t1 < 1) {
        edge.vb = this.createVertex(ax+t1*dx, ay+t1*dy);
        }

    // va and/or vb were clipped, thus we will need to close
    // cells which use this edge.
    if ( t0 > 0 || t1 < 1 ) {
        this.cells[edge.lSite.voronoiId].closeMe = true;
        this.cells[edge.rSite.voronoiId].closeMe = true;
    }

    return true;
    };

// Connect/cut edges at bounding box
Voronoi.prototype.clipEdges = function(bbox) {
    // connect all dangling edges to bounding box
    // or get rid of them if it can't be done
    var edges = this.edges,
        iEdge = edges.length,
        edge,
        abs_fn = Math.abs;

    // iterate backward so we can splice safely
    while (iEdge--) {
        edge = edges[iEdge];
        // edge is removed if:
        //   it is wholly outside the bounding box
        //   it is looking more like a point than a line
        if (!this.connectEdge(edge, bbox) ||
            !this.clipEdge(edge, bbox) ||
            (abs_fn(edge.va.x-edge.vb.x)<1e-9 && abs_fn(edge.va.y-edge.vb.y)<1e-9)) {
            edge.va = edge.vb = null;
            edges.splice(iEdge,1);
            }
        }
    };

// Close the cells.
// The cells are bound by the supplied bounding box.
// Each cell refers to its associated site, and a list
// of halfedges ordered counterclockwise.
Voronoi.prototype.closeCells = function(bbox) {
    var xl = bbox.xl,
        xr = bbox.xr,
        yt = bbox.yt,
        yb = bbox.yb,
        cells = this.cells,
        iCell = cells.length,
        cell,
        iLeft,
        halfedges, nHalfedges,
        edge,
        va, vb, vz,
        lastBorderSegment,
        abs_fn = Math.abs;

    while (iCell--) {
        cell = cells[iCell];
        // prune, order halfedges counterclockwise, then add missing ones
        // required to close cells
        if (!cell.prepareHalfedges()) {
            continue;
            }
        if (!cell.closeMe) {
            continue;
            }
        // find first 'unclosed' point.
        // an 'unclosed' point will be the end point of a halfedge which
        // does not match the start point of the following halfedge
        halfedges = cell.halfedges;
        nHalfedges = halfedges.length;
        // special case: only one site, in which case, the viewport is the cell
        // ...

        // all other cases
        iLeft = 0;
        while (iLeft < nHalfedges) {
            va = halfedges[iLeft].getEndpoint();
            vz = halfedges[(iLeft+1) % nHalfedges].getStartpoint();
            // if end point is not equal to start point, we need to add the missing
            // halfedge(s) up to vz
            if (abs_fn(va.x-vz.x)>=1e-9 || abs_fn(va.y-vz.y)>=1e-9) {

                // rhill 2013-12-02:
                // "Holes" in the halfedges are not necessarily always adjacent.
                // https://github.com/gorhill/Javascript-Voronoi/issues/16

                // find entry point:
                switch (true) {

                    // walk downward along left side
                    case this.equalWithEpsilon(va.x,xl) && this.lessThanWithEpsilon(va.y,yb):
                        lastBorderSegment = this.equalWithEpsilon(vz.x,xl);
                        vb = this.createVertex(xl, lastBorderSegment ? vz.y : yb);
                        edge = this.createBorderEdge(cell.site, va, vb);
                        iLeft++;
                        halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
                        nHalfedges++;
                        if ( lastBorderSegment ) { break; }
                        va = vb;
                        // fall through

                    // walk rightward along bottom side
                    case this.equalWithEpsilon(va.y,yb) && this.lessThanWithEpsilon(va.x,xr):
                        lastBorderSegment = this.equalWithEpsilon(vz.y,yb);
                        vb = this.createVertex(lastBorderSegment ? vz.x : xr, yb);
                        edge = this.createBorderEdge(cell.site, va, vb);
                        iLeft++;
                        halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
                        nHalfedges++;
                        if ( lastBorderSegment ) { break; }
                        va = vb;
                        // fall through

                    // walk upward along right side
                    case this.equalWithEpsilon(va.x,xr) && this.greaterThanWithEpsilon(va.y,yt):
                        lastBorderSegment = this.equalWithEpsilon(vz.x,xr);
                        vb = this.createVertex(xr, lastBorderSegment ? vz.y : yt);
                        edge = this.createBorderEdge(cell.site, va, vb);
                        iLeft++;
                        halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
                        nHalfedges++;
                        if ( lastBorderSegment ) { break; }
                        va = vb;
                        // fall through

                    // walk leftward along top side
                    case this.equalWithEpsilon(va.y,yt) && this.greaterThanWithEpsilon(va.x,xl):
                        lastBorderSegment = this.equalWithEpsilon(vz.y,yt);
                        vb = this.createVertex(lastBorderSegment ? vz.x : xl, yt);
                        edge = this.createBorderEdge(cell.site, va, vb);
                        iLeft++;
                        halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
                        nHalfedges++;
                        if ( lastBorderSegment ) { break; }
                        va = vb;
                        // fall through

                        // walk downward along left side
                        lastBorderSegment = this.equalWithEpsilon(vz.x,xl);
                        vb = this.createVertex(xl, lastBorderSegment ? vz.y : yb);
                        edge = this.createBorderEdge(cell.site, va, vb);
                        iLeft++;
                        halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
                        nHalfedges++;
                        if ( lastBorderSegment ) { break; }
                        va = vb;
                        // fall through

                        // walk rightward along bottom side
                        lastBorderSegment = this.equalWithEpsilon(vz.y,yb);
                        vb = this.createVertex(lastBorderSegment ? vz.x : xr, yb);
                        edge = this.createBorderEdge(cell.site, va, vb);
                        iLeft++;
                        halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
                        nHalfedges++;
                        if ( lastBorderSegment ) { break; }
                        va = vb;
                        // fall through

                        // walk upward along right side
                        lastBorderSegment = this.equalWithEpsilon(vz.x,xr);
                        vb = this.createVertex(xr, lastBorderSegment ? vz.y : yt);
                        edge = this.createBorderEdge(cell.site, va, vb);
                        iLeft++;
                        halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
                        nHalfedges++;
                        if ( lastBorderSegment ) { break; }
                        // fall through

                    default:
                        throw "Voronoi.closeCells() > this makes no sense!";
                    }
                }
            iLeft++;
            }
        cell.closeMe = false;
        }
    };

// ---------------------------------------------------------------------------
// Debugging helper
/*
Voronoi.prototype.dumpBeachline = function(y) {
    console.log('Voronoi.dumpBeachline(%f) > Beachsections, from left to right:', y);
    if ( !this.beachline ) {
        console.log('  None');
        }
    else {
        var bs = this.beachline.getFirst(this.beachline.root);
        while ( bs ) {
            console.log('  site %d: xl: %f, xr: %f', bs.site.voronoiId, this.leftBreakPoint(bs, y), this.rightBreakPoint(bs, y));
            bs = bs.rbNext;
            }
        }
    };
*/

// ---------------------------------------------------------------------------
// Helper: Quantize sites

// rhill 2013-10-12:
// This is to solve https://github.com/gorhill/Javascript-Voronoi/issues/15
// Since not all users will end up using the kind of coord values which would
// cause the issue to arise, I chose to let the user decide whether or not
// he should sanitize his coord values through this helper. This way, for
// those users who uses coord values which are known to be fine, no overhead is
// added.

Voronoi.prototype.quantizeSites = function(sites) {
    var ε = this.ε,
        n = sites.length,
        site;
    while ( n-- ) {
        site = sites[n];
        site.x = Math.floor(site.x / ε) * ε;
        site.y = Math.floor(site.y / ε) * ε;
        }
    };

// ---------------------------------------------------------------------------
// Helper: Recycle diagram: all vertex, edge and cell objects are
// "surrendered" to the Voronoi object for reuse.
// TODO: rhill-voronoi-core v2: more performance to be gained
// when I change the semantic of what is returned.

Voronoi.prototype.recycle = function(diagram) {
    if ( diagram ) {
        if ( diagram instanceof this.Diagram ) {
            this.toRecycle = diagram;
            }
        else {
            throw 'Voronoi.recycleDiagram() > Need a Diagram object.';
            }
        }
    };

// ---------------------------------------------------------------------------
// Top-level Fortune loop

// rhill 2011-05-19:
//   Voronoi sites are kept client-side now, to allow
//   user to freely modify content. At compute time,
//   *references* to sites are copied locally.

Voronoi.prototype.compute = function(sites, bbox) {
    // to measure execution time
    var startTime = new Date();

    // init internal state
    this.reset();

    // any diagram data available for recycling?
    // I do that here so that this is included in execution time
    if ( this.toRecycle ) {
        this.vertexJunkyard = this.vertexJunkyard.concat(this.toRecycle.vertices);
        this.edgeJunkyard = this.edgeJunkyard.concat(this.toRecycle.edges);
        this.cellJunkyard = this.cellJunkyard.concat(this.toRecycle.cells);
        this.toRecycle = null;
        }

    // Initialize site event queue
    var siteEvents = sites.slice(0);
    siteEvents.sort(function(a,b){
        var r = b.y - a.y;
        if (r) {return r;}
        return b.x - a.x;
        });

    // process queue
    var site = siteEvents.pop(),
        siteid = 0,
        xsitex, // to avoid duplicate sites
        xsitey,
        cells = this.cells,
        circle;

    // main loop
    for (;;) {
        // we need to figure whether we handle a site or circle event
        // for this we find out if there is a site event and it is
        // 'earlier' than the circle event
        circle = this.firstCircleEvent;

        // add beach section
        if (site && (!circle || site.y < circle.y || (site.y === circle.y && site.x < circle.x))) {
            // only if site is not a duplicate
            if (site.x !== xsitex || site.y !== xsitey) {
                // first create cell for new site
                cells[siteid] = this.createCell(site);
                site.voronoiId = siteid++;
                // then create a beachsection for that site
                this.addBeachsection(site);
                // remember last site coords to detect duplicate
                xsitey = site.y;
                xsitex = site.x;
                }
            site = siteEvents.pop();
            }

        // remove beach section
        else if (circle) {
            this.removeBeachsection(circle.arc);
            }

        // all done, quit
        else {
            break;
            }
        }

    // wrapping-up:
    //   connect dangling edges to bounding box
    //   cut edges as per bounding box
    //   discard edges completely outside bounding box
    //   discard edges which are point-like
    this.clipEdges(bbox);

    //   add missing edges in order to close opened cells
    this.closeCells(bbox);

    // to measure execution time
    var stopTime = new Date();

    // prepare return values
    var diagram = new this.Diagram();
    diagram.cells = this.cells;
    diagram.edges = this.edges;
    diagram.vertices = this.vertices;
    diagram.execTime = stopTime.getTime()-startTime.getTime();

    // clean up
    this.reset();

    return diagram;
    };

module.exports = Voronoi;

},{}]},{},[2])
//# sourceMappingURL=data:application/json;charset:utf-8;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbIm5vZGVfbW9kdWxlcy9icm93c2VyaWZ5L25vZGVfbW9kdWxlcy9icm93c2VyLXBhY2svX3ByZWx1ZGUuanMiLCJzcmMvZm9vZ3JhcGguanMiLCJzcmMvaW5kZXguanMiLCJzcmMvbGF5b3V0LmpzIiwic3JjL3JoaWxsLXZvcm9ub2ktY29yZS5qcyJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQTtBQ0FBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQzV3QkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDM0JBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUN2ZkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQSIsImZpbGUiOiJnZW5lcmF0ZWQuanMiLCJzb3VyY2VSb290IjoiIiwic291cmNlc0NvbnRlbnQiOlsiKGZ1bmN0aW9uIGUodCxuLHIpe2Z1bmN0aW9uIHMobyx1KXtpZighbltvXSl7aWYoIXRbb10pe3ZhciBhPXR5cGVvZiByZXF1aXJlPT1cImZ1bmN0aW9uXCImJnJlcXVpcmU7aWYoIXUmJmEpcmV0dXJuIGEobywhMCk7aWYoaSlyZXR1cm4gaShvLCEwKTt2YXIgZj1uZXcgRXJyb3IoXCJDYW5ub3QgZmluZCBtb2R1bGUgJ1wiK28rXCInXCIpO3Rocm93IGYuY29kZT1cIk1PRFVMRV9OT1RfRk9VTkRcIixmfXZhciBsPW5bb109e2V4cG9ydHM6e319O3Rbb11bMF0uY2FsbChsLmV4cG9ydHMsZnVuY3Rpb24oZSl7dmFyIG49dFtvXVsxXVtlXTtyZXR1cm4gcyhuP246ZSl9LGwsbC5leHBvcnRzLGUsdCxuLHIpfXJldHVybiBuW29dLmV4cG9ydHN9dmFyIGk9dHlwZW9mIHJlcXVpcmU9PVwiZnVuY3Rpb25cIiYmcmVxdWlyZTtmb3IodmFyIG89MDtvPHIubGVuZ3RoO28rKylzKHJbb10pO3JldHVybiBzfSkiLCJ2YXIgZm9vZ3JhcGggPSB7XG4gIC8qKlxuICAgKiBJbnNlcnQgYSB2ZXJ0ZXggaW50byB0aGlzIGdyYXBoLlxuICAgKlxuICAgKiBAcGFyYW0gdmVydGV4IEEgdmFsaWQgVmVydGV4IGluc3RhbmNlXG4gICAqL1xuICBpbnNlcnRWZXJ0ZXg6IGZ1bmN0aW9uKHZlcnRleCkge1xuICAgICAgdGhpcy52ZXJ0aWNlcy5wdXNoKHZlcnRleCk7XG4gICAgICB0aGlzLnZlcnRleENvdW50Kys7XG4gICAgfSxcblxuICAvKipcbiAgICogSW5zZXJ0IGFuIGVkZ2UgdmVydGV4MSAtLT4gdmVydGV4Mi5cbiAgICpcbiAgICogQHBhcmFtIGxhYmVsIExhYmVsIGZvciB0aGlzIGVkZ2VcbiAgICogQHBhcmFtIHdlaWdodCBXZWlnaHQgb2YgdGhpcyBlZGdlXG4gICAqIEBwYXJhbSB2ZXJ0ZXgxIFN0YXJ0aW5nIFZlcnRleCBpbnN0YW5jZVxuICAgKiBAcGFyYW0gdmVydGV4MiBFbmRpbmcgVmVydGV4IGluc3RhbmNlXG4gICAqIEByZXR1cm4gTmV3bHkgY3JlYXRlZCBFZGdlIGluc3RhbmNlXG4gICAqL1xuICBpbnNlcnRFZGdlOiBmdW5jdGlvbihsYWJlbCwgd2VpZ2h0LCB2ZXJ0ZXgxLCB2ZXJ0ZXgyLCBzdHlsZSkge1xuICAgICAgdmFyIGUxID0gbmV3IGZvb2dyYXBoLkVkZ2UobGFiZWwsIHdlaWdodCwgdmVydGV4Miwgc3R5bGUpO1xuICAgICAgdmFyIGUyID0gbmV3IGZvb2dyYXBoLkVkZ2UobnVsbCwgd2VpZ2h0LCB2ZXJ0ZXgxLCBudWxsKTtcblxuICAgICAgdmVydGV4MS5lZGdlcy5wdXNoKGUxKTtcbiAgICAgIHZlcnRleDIucmV2ZXJzZUVkZ2VzLnB1c2goZTIpO1xuXG4gICAgICByZXR1cm4gZTE7XG4gICAgfSxcblxuICAvKipcbiAgICogRGVsZXRlIGVkZ2UuXG4gICAqXG4gICAqIEBwYXJhbSB2ZXJ0ZXggU3RhcnRpbmcgdmVydGV4XG4gICAqIEBwYXJhbSBlZGdlIEVkZ2UgdG8gcmVtb3ZlXG4gICAqL1xuICByZW1vdmVFZGdlOiBmdW5jdGlvbih2ZXJ0ZXgxLCB2ZXJ0ZXgyKSB7XG4gICAgICBmb3IgKHZhciBpID0gdmVydGV4MS5lZGdlcy5sZW5ndGggLSAxOyBpID49IDA7IGktLSkge1xuICAgICAgICBpZiAodmVydGV4MS5lZGdlc1tpXS5lbmRWZXJ0ZXggPT0gdmVydGV4Mikge1xuICAgICAgICAgIHZlcnRleDEuZWRnZXMuc3BsaWNlKGksMSk7XG4gICAgICAgICAgYnJlYWs7XG4gICAgICAgIH1cbiAgICAgIH1cblxuICAgICAgZm9yICh2YXIgaSA9IHZlcnRleDIucmV2ZXJzZUVkZ2VzLmxlbmd0aCAtIDE7IGkgPj0gMDsgaS0tKSB7XG4gICAgICAgIGlmICh2ZXJ0ZXgyLnJldmVyc2VFZGdlc1tpXS5lbmRWZXJ0ZXggPT0gdmVydGV4MSkge1xuICAgICAgICAgIHZlcnRleDIucmV2ZXJzZUVkZ2VzLnNwbGljZShpLDEpO1xuICAgICAgICAgIGJyZWFrO1xuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcblxuICAvKipcbiAgICogRGVsZXRlIHZlcnRleC5cbiAgICpcbiAgICogQHBhcmFtIHZlcnRleCBWZXJ0ZXggdG8gcmVtb3ZlIGZyb20gdGhlIGdyYXBoXG4gICAqL1xuICByZW1vdmVWZXJ0ZXg6IGZ1bmN0aW9uKHZlcnRleCkge1xuICAgICAgZm9yICh2YXIgaSA9IHZlcnRleC5lZGdlcy5sZW5ndGggLSAxOyBpID49IDA7IGktLSApIHtcbiAgICAgICAgdGhpcy5yZW1vdmVFZGdlKHZlcnRleCwgdmVydGV4LmVkZ2VzW2ldLmVuZFZlcnRleCk7XG4gICAgICB9XG5cbiAgICAgIGZvciAodmFyIGkgPSB2ZXJ0ZXgucmV2ZXJzZUVkZ2VzLmxlbmd0aCAtIDE7IGkgPj0gMDsgaS0tICkge1xuICAgICAgICB0aGlzLnJlbW92ZUVkZ2UodmVydGV4LnJldmVyc2VFZGdlc1tpXS5lbmRWZXJ0ZXgsIHZlcnRleCk7XG4gICAgICB9XG5cbiAgICAgIGZvciAodmFyIGkgPSB0aGlzLnZlcnRpY2VzLmxlbmd0aCAtIDE7IGkgPj0gMDsgaS0tICkge1xuICAgICAgICBpZiAodGhpcy52ZXJ0aWNlc1tpXSA9PSB2ZXJ0ZXgpIHtcbiAgICAgICAgICB0aGlzLnZlcnRpY2VzLnNwbGljZShpLDEpO1xuICAgICAgICAgIGJyZWFrO1xuICAgICAgICB9XG4gICAgICB9XG5cbiAgICAgIHRoaXMudmVydGV4Q291bnQtLTtcbiAgICB9LFxuXG4gIC8qKlxuICAgKiBQbG90cyB0aGlzIGdyYXBoIHRvIGEgY2FudmFzLlxuICAgKlxuICAgKiBAcGFyYW0gY2FudmFzIEEgcHJvcGVyIGNhbnZhcyBpbnN0YW5jZVxuICAgKi9cbiAgcGxvdDogZnVuY3Rpb24oY2FudmFzKSB7XG4gICAgICB2YXIgaSA9IDA7XG4gICAgICAvKiBEcmF3IGVkZ2VzIGZpcnN0ICovXG4gICAgICBmb3IgKGkgPSAwOyBpIDwgdGhpcy52ZXJ0aWNlcy5sZW5ndGg7IGkrKykge1xuICAgICAgICB2YXIgdiA9IHRoaXMudmVydGljZXNbaV07XG4gICAgICAgIGlmICghdi5oaWRkZW4pIHtcbiAgICAgICAgICBmb3IgKHZhciBqID0gMDsgaiA8IHYuZWRnZXMubGVuZ3RoOyBqKyspIHtcbiAgICAgICAgICAgIHZhciBlID0gdi5lZGdlc1tqXTtcbiAgICAgICAgICAgIC8qIERyYXcgZWRnZSAoaWYgbm90IGhpZGRlbikgKi9cbiAgICAgICAgICAgIGlmICghZS5oaWRkZW4pXG4gICAgICAgICAgICAgIGUuZHJhdyhjYW52YXMsIHYpO1xuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuXG4gICAgICAvKiBEcmF3IHRoZSB2ZXJ0aWNlcy4gKi9cbiAgICAgIGZvciAoaSA9IDA7IGkgPCB0aGlzLnZlcnRpY2VzLmxlbmd0aDsgaSsrKSB7XG4gICAgICAgIHYgPSB0aGlzLnZlcnRpY2VzW2ldO1xuXG4gICAgICAgIC8qIERyYXcgdmVydGV4IChpZiBub3QgaGlkZGVuKSAqL1xuICAgICAgICBpZiAoIXYuaGlkZGVuKVxuICAgICAgICAgIHYuZHJhdyhjYW52YXMpO1xuICAgICAgfVxuICAgIH0sXG5cbiAgLyoqXG4gICAqIEdyYXBoIG9iamVjdCBjb25zdHJ1Y3Rvci5cbiAgICpcbiAgICogQHBhcmFtIGxhYmVsIExhYmVsIG9mIHRoaXMgZ3JhcGhcbiAgICogQHBhcmFtIGRpcmVjdGVkIHRydWUgb3IgZmFsc2VcbiAgICovXG4gIEdyYXBoOiBmdW5jdGlvbiAobGFiZWwsIGRpcmVjdGVkKSB7XG4gICAgICAvKiBGaWVsZHMuICovXG4gICAgICB0aGlzLmxhYmVsID0gbGFiZWw7XG4gICAgICB0aGlzLnZlcnRpY2VzID0gbmV3IEFycmF5KCk7XG4gICAgICB0aGlzLmRpcmVjdGVkID0gZGlyZWN0ZWQ7XG4gICAgICB0aGlzLnZlcnRleENvdW50ID0gMDtcblxuICAgICAgLyogR3JhcGggbWV0aG9kcy4gKi9cbiAgICAgIHRoaXMuaW5zZXJ0VmVydGV4ID0gZm9vZ3JhcGguaW5zZXJ0VmVydGV4O1xuICAgICAgdGhpcy5yZW1vdmVWZXJ0ZXggPSBmb29ncmFwaC5yZW1vdmVWZXJ0ZXg7XG4gICAgICB0aGlzLmluc2VydEVkZ2UgPSBmb29ncmFwaC5pbnNlcnRFZGdlO1xuICAgICAgdGhpcy5yZW1vdmVFZGdlID0gZm9vZ3JhcGgucmVtb3ZlRWRnZTtcbiAgICAgIHRoaXMucGxvdCA9IGZvb2dyYXBoLnBsb3Q7XG4gICAgfSxcblxuICAvKipcbiAgICogVmVydGV4IG9iamVjdCBjb25zdHJ1Y3Rvci5cbiAgICpcbiAgICogQHBhcmFtIGxhYmVsIExhYmVsIG9mIHRoaXMgdmVydGV4XG4gICAqIEBwYXJhbSBuZXh0IFJlZmVyZW5jZSB0byB0aGUgbmV4dCB2ZXJ0ZXggb2YgdGhpcyBncmFwaFxuICAgKiBAcGFyYW0gZmlyc3RFZGdlIEZpcnN0IGVkZ2Ugb2YgYSBsaW5rZWQgbGlzdCBvZiBlZGdlc1xuICAgKi9cbiAgVmVydGV4OiBmdW5jdGlvbihsYWJlbCwgeCwgeSwgc3R5bGUpIHtcbiAgICAgIHRoaXMubGFiZWwgPSBsYWJlbDtcbiAgICAgIHRoaXMuZWRnZXMgPSBuZXcgQXJyYXkoKTtcbiAgICAgIHRoaXMucmV2ZXJzZUVkZ2VzID0gbmV3IEFycmF5KCk7XG4gICAgICB0aGlzLnggPSB4O1xuICAgICAgdGhpcy55ID0geTtcbiAgICAgIHRoaXMuZHggPSAwO1xuICAgICAgdGhpcy5keSA9IDA7XG4gICAgICB0aGlzLmxldmVsID0gLTE7XG4gICAgICB0aGlzLm51bWJlck9mUGFyZW50cyA9IDA7XG4gICAgICB0aGlzLmhpZGRlbiA9IGZhbHNlO1xuICAgICAgdGhpcy5maXhlZCA9IGZhbHNlOyAgICAgLy8gRml4ZWQgdmVydGljZXMgYXJlIHN0YXRpYyAodW5tb3ZhYmxlKVxuXG4gICAgICBpZihzdHlsZSAhPSBudWxsKSB7XG4gICAgICAgICAgdGhpcy5zdHlsZSA9IHN0eWxlO1xuICAgICAgfVxuICAgICAgZWxzZSB7IC8vIERlZmF1bHRcbiAgICAgICAgICB0aGlzLnN0eWxlID0gbmV3IGZvb2dyYXBoLlZlcnRleFN0eWxlKCdlbGxpcHNlJywgODAsIDQwLCAnI2ZmZmZmZicsICcjMDAwMDAwJywgdHJ1ZSk7XG4gICAgICB9XG4gICAgfSxcblxuXG4gICAvKipcbiAgICogVmVydGV4U3R5bGUgb2JqZWN0IHR5cGUgZm9yIGRlZmluaW5nIHZlcnRleCBzdHlsZSBvcHRpb25zLlxuICAgKlxuICAgKiBAcGFyYW0gc2hhcGUgU2hhcGUgb2YgdGhlIHZlcnRleCAoJ2VsbGlwc2UnIG9yICdyZWN0JylcbiAgICogQHBhcmFtIHdpZHRoIFdpZHRoIGluIHB4XG4gICAqIEBwYXJhbSBoZWlnaHQgSGVpZ2h0IGluIHB4XG4gICAqIEBwYXJhbSBmaWxsQ29sb3IgVGhlIGNvbG9yIHdpdGggd2hpY2ggdGhlIHZlcnRleCBpcyBkcmF3biAoUkdCIEhFWCBzdHJpbmcpXG4gICAqIEBwYXJhbSBib3JkZXJDb2xvciBUaGUgY29sb3Igd2l0aCB3aGljaCB0aGUgYm9yZGVyIG9mIHRoZSB2ZXJ0ZXggaXMgZHJhd24gKFJHQiBIRVggc3RyaW5nKVxuICAgKiBAcGFyYW0gc2hvd0xhYmVsIFNob3cgdGhlIHZlcnRleCBsYWJlbCBvciBub3RcbiAgICovXG4gIFZlcnRleFN0eWxlOiBmdW5jdGlvbihzaGFwZSwgd2lkdGgsIGhlaWdodCwgZmlsbENvbG9yLCBib3JkZXJDb2xvciwgc2hvd0xhYmVsKSB7XG4gICAgICB0aGlzLnNoYXBlID0gc2hhcGU7XG4gICAgICB0aGlzLndpZHRoID0gd2lkdGg7XG4gICAgICB0aGlzLmhlaWdodCA9IGhlaWdodDtcbiAgICAgIHRoaXMuZmlsbENvbG9yID0gZmlsbENvbG9yO1xuICAgICAgdGhpcy5ib3JkZXJDb2xvciA9IGJvcmRlckNvbG9yO1xuICAgICAgdGhpcy5zaG93TGFiZWwgPSBzaG93TGFiZWw7XG4gICAgfSxcblxuICAvKipcbiAgICogRWRnZSBvYmplY3QgY29uc3RydWN0b3IuXG4gICAqXG4gICAqIEBwYXJhbSBsYWJlbCBMYWJlbCBvZiB0aGlzIGVkZ2VcbiAgICogQHBhcmFtIG5leHQgTmV4dCBlZGdlIHJlZmVyZW5jZVxuICAgKiBAcGFyYW0gd2VpZ2h0IEVkZ2Ugd2VpZ2h0XG4gICAqIEBwYXJhbSBlbmRWZXJ0ZXggRGVzdGluYXRpb24gVmVydGV4IGluc3RhbmNlXG4gICAqL1xuICBFZGdlOiBmdW5jdGlvbiAobGFiZWwsIHdlaWdodCwgZW5kVmVydGV4LCBzdHlsZSkge1xuICAgICAgdGhpcy5sYWJlbCA9IGxhYmVsO1xuICAgICAgdGhpcy53ZWlnaHQgPSB3ZWlnaHQ7XG4gICAgICB0aGlzLmVuZFZlcnRleCA9IGVuZFZlcnRleDtcbiAgICAgIHRoaXMuc3R5bGUgPSBudWxsO1xuICAgICAgdGhpcy5oaWRkZW4gPSBmYWxzZTtcblxuICAgICAgLy8gQ3VydmluZyBpbmZvcm1hdGlvblxuICAgICAgdGhpcy5jdXJ2ZWQgPSBmYWxzZTtcbiAgICAgIHRoaXMuY29udHJvbFggPSAtMTsgICAvLyBDb250cm9sIGNvb3JkaW5hdGVzIGZvciBCZXppZXIgY3VydmUgZHJhd2luZ1xuICAgICAgdGhpcy5jb250cm9sWSA9IC0xO1xuICAgICAgdGhpcy5vcmlnaW5hbCA9IG51bGw7IC8vIElmIHRoaXMgaXMgYSB0ZW1wb3JhcnkgZWRnZSBpdCBob2xkcyB0aGUgb3JpZ2luYWwgZWRnZVxuXG4gICAgICBpZihzdHlsZSAhPSBudWxsKSB7XG4gICAgICAgIHRoaXMuc3R5bGUgPSBzdHlsZTtcbiAgICAgIH1cbiAgICAgIGVsc2UgeyAgLy8gU2V0IHRvIGRlZmF1bHRcbiAgICAgICAgdGhpcy5zdHlsZSA9IG5ldyBmb29ncmFwaC5FZGdlU3R5bGUoMiwgJyMwMDAwMDAnLCB0cnVlLCBmYWxzZSk7XG4gICAgICB9XG4gICAgfSxcblxuXG5cbiAgLyoqXG4gICAqIEVkZ2VTdHlsZSBvYmplY3QgdHlwZSBmb3IgZGVmaW5pbmcgdmVydGV4IHN0eWxlIG9wdGlvbnMuXG4gICAqXG4gICAqIEBwYXJhbSB3aWR0aCBFZGdlIGxpbmUgd2lkdGhcbiAgICogQHBhcmFtIGNvbG9yIFRoZSBjb2xvciB3aXRoIHdoaWNoIHRoZSBlZGdlIGlzIGRyYXduXG4gICAqIEBwYXJhbSBzaG93QXJyb3cgRHJhdyB0aGUgZWRnZSBhcnJvdyAob25seSBpZiBkaXJlY3RlZClcbiAgICogQHBhcmFtIHNob3dMYWJlbCBTaG93IHRoZSBlZGdlIGxhYmVsIG9yIG5vdFxuICAgKi9cbiAgRWRnZVN0eWxlOiBmdW5jdGlvbih3aWR0aCwgY29sb3IsIHNob3dBcnJvdywgc2hvd0xhYmVsKSB7XG4gICAgICB0aGlzLndpZHRoID0gd2lkdGg7XG4gICAgICB0aGlzLmNvbG9yID0gY29sb3I7XG4gICAgICB0aGlzLnNob3dBcnJvdyA9IHNob3dBcnJvdztcbiAgICAgIHRoaXMuc2hvd0xhYmVsID0gc2hvd0xhYmVsO1xuICAgIH0sXG5cbiAgLyoqXG4gICAqIFRoaXMgZmlsZSBpcyBwYXJ0IG9mIGZvb2dyYXBoIEphdmFzY3JpcHQgZ3JhcGggbGlicmFyeS5cbiAgICpcbiAgICogRGVzY3JpcHRpb246IFJhbmRvbSB2ZXJ0ZXggbGF5b3V0IG1hbmFnZXJcbiAgICovXG5cbiAgLyoqXG4gICAqIENsYXNzIGNvbnN0cnVjdG9yLlxuICAgKlxuICAgKiBAcGFyYW0gd2lkdGggTGF5b3V0IHdpZHRoXG4gICAqIEBwYXJhbSBoZWlnaHQgTGF5b3V0IGhlaWdodFxuICAgKi9cbiAgUmFuZG9tVmVydGV4TGF5b3V0OiBmdW5jdGlvbiAod2lkdGgsIGhlaWdodCkge1xuICAgICAgdGhpcy53aWR0aCA9IHdpZHRoO1xuICAgICAgdGhpcy5oZWlnaHQgPSBoZWlnaHQ7XG4gICAgfSxcblxuXG4gIC8qKlxuICAgKiBUaGlzIGZpbGUgaXMgcGFydCBvZiBmb29ncmFwaCBKYXZhc2NyaXB0IGdyYXBoIGxpYnJhcnkuXG4gICAqXG4gICAqIERlc2NyaXB0aW9uOiBGcnVjaHRlcm1hbi1SZWluZ29sZCBmb3JjZS1kaXJlY3RlZCB2ZXJ0ZXhcbiAgICogICAgICAgICAgICAgIGxheW91dCBtYW5hZ2VyXG4gICAqL1xuXG4gIC8qKlxuICAgKiBDbGFzcyBjb25zdHJ1Y3Rvci5cbiAgICpcbiAgICogQHBhcmFtIHdpZHRoIExheW91dCB3aWR0aFxuICAgKiBAcGFyYW0gaGVpZ2h0IExheW91dCBoZWlnaHRcbiAgICogQHBhcmFtIGl0ZXJhdGlvbnMgTnVtYmVyIG9mIGl0ZXJhdGlvbnMgLVxuICAgKiB3aXRoIG1vcmUgaXRlcmF0aW9ucyBpdCBpcyBtb3JlIGxpa2VseSB0aGUgbGF5b3V0IGhhcyBjb252ZXJnZWQgaW50byBhIHN0YXRpYyBlcXVpbGlicml1bS5cbiAgICovXG4gIEZvcmNlRGlyZWN0ZWRWZXJ0ZXhMYXlvdXQ6IGZ1bmN0aW9uICh3aWR0aCwgaGVpZ2h0LCBpdGVyYXRpb25zLCByYW5kb21pemUsIGVwcykge1xuICAgICAgdGhpcy53aWR0aCA9IHdpZHRoO1xuICAgICAgdGhpcy5oZWlnaHQgPSBoZWlnaHQ7XG4gICAgICB0aGlzLml0ZXJhdGlvbnMgPSBpdGVyYXRpb25zO1xuICAgICAgdGhpcy5yYW5kb21pemUgPSByYW5kb21pemU7XG4gICAgICB0aGlzLmVwcyA9IGVwcztcbiAgICAgIHRoaXMuY2FsbGJhY2sgPSBmdW5jdGlvbigpIHt9O1xuICAgIH0sXG5cbiAgQTogMS41LCAvLyBGaW5lIHR1bmUgYXR0cmFjdGlvblxuXG4gIFI6IDAuNSAgLy8gRmluZSB0dW5lIHJlcHVsc2lvblxufTtcblxuLyoqXG4gKiB0b1N0cmluZyBvdmVybG9hZCBmb3IgZWFzaWVyIGRlYnVnZ2luZ1xuICovXG5mb29ncmFwaC5WZXJ0ZXgucHJvdG90eXBlLnRvU3RyaW5nID0gZnVuY3Rpb24oKSB7XG4gIHJldHVybiBcIlt2OlwiICsgdGhpcy5sYWJlbCArIFwiXSBcIjtcbn07XG5cbi8qKlxuICogdG9TdHJpbmcgb3ZlcmxvYWQgZm9yIGVhc2llciBkZWJ1Z2dpbmdcbiAqL1xuZm9vZ3JhcGguRWRnZS5wcm90b3R5cGUudG9TdHJpbmcgPSBmdW5jdGlvbigpIHtcbiAgcmV0dXJuIFwiW2U6XCIgKyB0aGlzLmVuZFZlcnRleC5sYWJlbCArIFwiXSBcIjtcbn07XG5cbi8qKlxuICogRHJhdyB2ZXJ0ZXggbWV0aG9kLlxuICpcbiAqIEBwYXJhbSBjYW52YXMganNHcmFwaGljcyBpbnN0YW5jZVxuICovXG5mb29ncmFwaC5WZXJ0ZXgucHJvdG90eXBlLmRyYXcgPSBmdW5jdGlvbihjYW52YXMpIHtcbiAgdmFyIHggPSB0aGlzLng7XG4gIHZhciB5ID0gdGhpcy55O1xuICB2YXIgd2lkdGggPSB0aGlzLnN0eWxlLndpZHRoO1xuICB2YXIgaGVpZ2h0ID0gdGhpcy5zdHlsZS5oZWlnaHQ7XG4gIHZhciBzaGFwZSA9IHRoaXMuc3R5bGUuc2hhcGU7XG5cbiAgY2FudmFzLnNldFN0cm9rZSgyKTtcbiAgY2FudmFzLnNldENvbG9yKHRoaXMuc3R5bGUuZmlsbENvbG9yKTtcblxuICBpZihzaGFwZSA9PSAncmVjdCcpIHtcbiAgICBjYW52YXMuZmlsbFJlY3QoeCwgeSwgd2lkdGgsIGhlaWdodCk7XG4gICAgY2FudmFzLnNldENvbG9yKHRoaXMuc3R5bGUuYm9yZGVyQ29sb3IpO1xuICAgIGNhbnZhcy5kcmF3UmVjdCh4LCB5LCB3aWR0aCwgaGVpZ2h0KTtcbiAgfVxuICBlbHNlIHsgLy8gRGVmYXVsdCB0byBlbGxpcHNlXG4gICAgY2FudmFzLmZpbGxFbGxpcHNlKHgsIHksIHdpZHRoLCBoZWlnaHQpO1xuICAgIGNhbnZhcy5zZXRDb2xvcih0aGlzLnN0eWxlLmJvcmRlckNvbG9yKTtcbiAgICBjYW52YXMuZHJhd0VsbGlwc2UoeCwgeSwgd2lkdGgsIGhlaWdodCk7XG4gIH1cblxuICBpZih0aGlzLnN0eWxlLnNob3dMYWJlbCkge1xuICAgIGNhbnZhcy5kcmF3U3RyaW5nUmVjdCh0aGlzLmxhYmVsLCB4LCB5ICsgaGVpZ2h0LzIgLSA3LCB3aWR0aCwgJ2NlbnRlcicpO1xuICB9XG59O1xuXG4vKipcbiAqIEZpdHMgdGhlIGdyYXBoIGludG8gdGhlIGJvdW5kaW5nIGJveFxuICpcbiAqIEBwYXJhbSB3aWR0aFxuICogQHBhcmFtIGhlaWdodFxuICogQHBhcmFtIHByZXNlcnZlQXNwZWN0XG4gKi9cbmZvb2dyYXBoLkdyYXBoLnByb3RvdHlwZS5ub3JtYWxpemUgPSBmdW5jdGlvbih3aWR0aCwgaGVpZ2h0LCBwcmVzZXJ2ZUFzcGVjdCkge1xuICBmb3IgKHZhciBpOCBpbiB0aGlzLnZlcnRpY2VzKSB7XG4gICAgdmFyIHYgPSB0aGlzLnZlcnRpY2VzW2k4XTtcbiAgICB2Lm9sZFggPSB2Lng7XG4gICAgdi5vbGRZID0gdi55O1xuICB9XG4gIHZhciBtbnggPSB3aWR0aCAgKiAwLjE7XG4gIHZhciBteHggPSB3aWR0aCAgKiAwLjk7XG4gIHZhciBtbnkgPSBoZWlnaHQgKiAwLjE7XG4gIHZhciBteHkgPSBoZWlnaHQgKiAwLjk7XG4gIGlmIChwcmVzZXJ2ZUFzcGVjdCA9PSBudWxsKVxuICAgIHByZXNlcnZlQXNwZWN0ID0gdHJ1ZTtcblxuICB2YXIgbWlueCA9IE51bWJlci5NQVhfVkFMVUU7XG4gIHZhciBtaW55ID0gTnVtYmVyLk1BWF9WQUxVRTtcbiAgdmFyIG1heHggPSBOdW1iZXIuTUlOX1ZBTFVFO1xuICB2YXIgbWF4eSA9IE51bWJlci5NSU5fVkFMVUU7XG5cbiAgZm9yICh2YXIgaTcgaW4gdGhpcy52ZXJ0aWNlcykge1xuICAgIHZhciB2ID0gdGhpcy52ZXJ0aWNlc1tpN107XG4gICAgaWYgKHYueCA8IG1pbngpIG1pbnggPSB2Lng7XG4gICAgaWYgKHYueSA8IG1pbnkpIG1pbnkgPSB2Lnk7XG4gICAgaWYgKHYueCA+IG1heHgpIG1heHggPSB2Lng7XG4gICAgaWYgKHYueSA+IG1heHkpIG1heHkgPSB2Lnk7XG4gIH1cbiAgdmFyIGt4ID0gKG14eC1tbngpIC8gKG1heHggLSBtaW54KTtcbiAgdmFyIGt5ID0gKG14eS1tbnkpIC8gKG1heHkgLSBtaW55KTtcblxuICBpZiAocHJlc2VydmVBc3BlY3QpIHtcbiAgICBreCA9IE1hdGgubWluKGt4LCBreSk7XG4gICAga3kgPSBNYXRoLm1pbihreCwga3kpO1xuICB9XG5cbiAgdmFyIG5ld01heHggPSBOdW1iZXIuTUlOX1ZBTFVFO1xuICB2YXIgbmV3TWF4eSA9IE51bWJlci5NSU5fVkFMVUU7XG4gIGZvciAodmFyIGk4IGluIHRoaXMudmVydGljZXMpIHtcbiAgICB2YXIgdiA9IHRoaXMudmVydGljZXNbaThdO1xuICAgIHYueCA9ICh2LnggLSBtaW54KSAqIGt4O1xuICAgIHYueSA9ICh2LnkgLSBtaW55KSAqIGt5O1xuICAgIGlmICh2LnggPiBuZXdNYXh4KSBuZXdNYXh4ID0gdi54O1xuICAgIGlmICh2LnkgPiBuZXdNYXh5KSBuZXdNYXh5ID0gdi55O1xuICB9XG5cbiAgdmFyIGR4ID0gKCB3aWR0aCAgLSBuZXdNYXh4ICkgLyAyLjA7XG4gIHZhciBkeSA9ICggaGVpZ2h0IC0gbmV3TWF4eSApIC8gMi4wO1xuICBmb3IgKHZhciBpOCBpbiB0aGlzLnZlcnRpY2VzKSB7XG4gICAgdmFyIHYgPSB0aGlzLnZlcnRpY2VzW2k4XTtcbiAgICB2LnggKz0gZHg7XG4gICAgdi55ICs9IGR5O1xuICB9XG59O1xuXG4vKipcbiAqIERyYXcgZWRnZSBtZXRob2QuIERyYXdzIGVkZ2UgXCJ2XCIgLS0+IFwidGhpc1wiLlxuICpcbiAqIEBwYXJhbSBjYW52YXMganNHcmFwaGljcyBpbnN0YW5jZVxuICogQHBhcmFtIHYgU3RhcnQgdmVydGV4XG4gKi9cbmZvb2dyYXBoLkVkZ2UucHJvdG90eXBlLmRyYXcgPSBmdW5jdGlvbihjYW52YXMsIHYpIHtcbiAgdmFyIHgxID0gTWF0aC5yb3VuZCh2LnggKyB2LnN0eWxlLndpZHRoLzIpO1xuICB2YXIgeTEgPSBNYXRoLnJvdW5kKHYueSArIHYuc3R5bGUuaGVpZ2h0LzIpO1xuICB2YXIgeDIgPSBNYXRoLnJvdW5kKHRoaXMuZW5kVmVydGV4LnggKyB0aGlzLmVuZFZlcnRleC5zdHlsZS53aWR0aC8yKTtcbiAgdmFyIHkyID0gTWF0aC5yb3VuZCh0aGlzLmVuZFZlcnRleC55ICsgdGhpcy5lbmRWZXJ0ZXguc3R5bGUuaGVpZ2h0LzIpO1xuXG4gIC8vIENvbnRyb2wgcG9pbnQgKG5lZWRlZCBvbmx5IGZvciBjdXJ2ZWQgZWRnZXMpXG4gIHZhciB4MyA9IHRoaXMuY29udHJvbFg7XG4gIHZhciB5MyA9IHRoaXMuY29udHJvbFk7XG5cbiAgLy8gQXJyb3cgdGlwIGFuZCBhbmdsZVxuICB2YXIgWF9USVAsIFlfVElQLCBBTkdMRTtcblxuICAvKiBRdWFkcmljIEJlemllciBjdXJ2ZSBkZWZpbml0aW9uLiAqL1xuICBmdW5jdGlvbiBCeCh0KSB7IHJldHVybiAoMS10KSooMS10KSp4MSArIDIqKDEtdCkqdCp4MyArIHQqdCp4MjsgfVxuICBmdW5jdGlvbiBCeSh0KSB7IHJldHVybiAoMS10KSooMS10KSp5MSArIDIqKDEtdCkqdCp5MyArIHQqdCp5MjsgfVxuXG4gIGNhbnZhcy5zZXRTdHJva2UodGhpcy5zdHlsZS53aWR0aCk7XG4gIGNhbnZhcy5zZXRDb2xvcih0aGlzLnN0eWxlLmNvbG9yKTtcblxuICBpZih0aGlzLmN1cnZlZCkgeyAvLyBEcmF3IGEgcXVhZHJpYyBCZXppZXIgY3VydmVcbiAgICB0aGlzLmN1cnZlZCA9IGZhbHNlOyAvLyBSZXNldFxuICAgIHZhciB0ID0gMCwgZHQgPSAxLzEwO1xuICAgIHZhciB4cyA9IHgxLCB5cyA9IHkxLCB4biwgeW47XG5cbiAgICB3aGlsZSAodCA8IDEtZHQpIHtcbiAgICAgIHQgKz0gZHQ7XG4gICAgICB4biA9IEJ4KHQpO1xuICAgICAgeW4gPSBCeSh0KTtcbiAgICAgIGNhbnZhcy5kcmF3TGluZSh4cywgeXMsIHhuLCB5bik7XG4gICAgICB4cyA9IHhuO1xuICAgICAgeXMgPSB5bjtcbiAgICB9XG5cbiAgICAvLyBTZXQgdGhlIGFycm93IHRpcCBjb29yZGluYXRlc1xuICAgIFhfVElQID0geHM7XG4gICAgWV9USVAgPSB5cztcblxuICAgIC8vIE1vdmUgdGhlIHRpcCB0byAoMCwwKSBhbmQgY2FsY3VsYXRlIHRoZSBhbmdsZVxuICAgIC8vIG9mIHRoZSBhcnJvdyBoZWFkXG4gICAgQU5HTEUgPSBhbmd1bGFyQ29vcmQoQngoMS0yKmR0KSAtIFhfVElQLCBCeSgxLTIqZHQpIC0gWV9USVApO1xuXG4gIH0gZWxzZSB7XG4gICAgY2FudmFzLmRyYXdMaW5lKHgxLCB5MSwgeDIsIHkyKTtcblxuICAgIC8vIFNldCB0aGUgYXJyb3cgdGlwIGNvb3JkaW5hdGVzXG4gICAgWF9USVAgPSB4MjtcbiAgICBZX1RJUCA9IHkyO1xuXG4gICAgLy8gTW92ZSB0aGUgdGlwIHRvICgwLDApIGFuZCBjYWxjdWxhdGUgdGhlIGFuZ2xlXG4gICAgLy8gb2YgdGhlIGFycm93IGhlYWRcbiAgICBBTkdMRSA9IGFuZ3VsYXJDb29yZCh4MSAtIFhfVElQLCB5MSAtIFlfVElQKTtcbiAgfVxuXG4gIGlmKHRoaXMuc3R5bGUuc2hvd0Fycm93KSB7XG4gICAgZHJhd0Fycm93KEFOR0xFLCBYX1RJUCwgWV9USVApO1xuICB9XG5cbiAgLy8gVE9ET1xuICBpZih0aGlzLnN0eWxlLnNob3dMYWJlbCkge1xuICB9XG5cbiAgLyoqXG4gICAqIERyYXdzIGFuIGVkZ2UgYXJyb3cuXG4gICAqIEBwYXJhbSBwaGkgVGhlIGFuZ2xlIChpbiByYWRpYW5zKSBvZiB0aGUgYXJyb3cgaW4gcG9sYXIgY29vcmRpbmF0ZXMuXG4gICAqIEBwYXJhbSB4IFggY29vcmRpbmF0ZSBvZiB0aGUgYXJyb3cgdGlwLlxuICAgKiBAcGFyYW0geSBZIGNvb3JkaW5hdGUgb2YgdGhlIGFycm93IHRpcC5cbiAgICovXG4gIGZ1bmN0aW9uIGRyYXdBcnJvdyhwaGksIHgsIHkpXG4gIHtcbiAgICAvLyBBcnJvdyBib3VuZGluZyBib3ggKGluIHB4KVxuICAgIHZhciBIID0gNTA7XG4gICAgdmFyIFcgPSAxMDtcblxuICAgIC8vIFNldCBjYXJ0ZXNpYW4gY29vcmRpbmF0ZXMgb2YgdGhlIGFycm93XG4gICAgdmFyIHAxMSA9IDAsIHAxMiA9IDA7XG4gICAgdmFyIHAyMSA9IEgsIHAyMiA9IFcvMjtcbiAgICB2YXIgcDMxID0gSCwgcDMyID0gLVcvMjtcblxuICAgIC8vIENvbnZlcnQgdG8gcG9sYXIgY29vcmRpbmF0ZXNcbiAgICB2YXIgcjIgPSByYWRpYWxDb29yZChwMjEsIHAyMik7XG4gICAgdmFyIHIzID0gcmFkaWFsQ29vcmQocDMxLCBwMzIpO1xuICAgIHZhciBwaGkyID0gYW5ndWxhckNvb3JkKHAyMSwgcDIyKTtcbiAgICB2YXIgcGhpMyA9IGFuZ3VsYXJDb29yZChwMzEsIHAzMik7XG5cbiAgICAvLyBSb3RhdGUgdGhlIGFycm93XG4gICAgcGhpMiArPSBwaGk7XG4gICAgcGhpMyArPSBwaGk7XG5cbiAgICAvLyBVcGRhdGUgY2FydGVzaWFuIGNvb3JkaW5hdGVzXG4gICAgcDIxID0gcjIgKiBNYXRoLmNvcyhwaGkyKTtcbiAgICBwMjIgPSByMiAqIE1hdGguc2luKHBoaTIpO1xuICAgIHAzMSA9IHIzICogTWF0aC5jb3MocGhpMyk7XG4gICAgcDMyID0gcjMgKiBNYXRoLnNpbihwaGkzKTtcblxuICAgIC8vIFRyYW5zbGF0ZVxuICAgIHAxMSArPSB4O1xuICAgIHAxMiArPSB5O1xuICAgIHAyMSArPSB4O1xuICAgIHAyMiArPSB5O1xuICAgIHAzMSArPSB4O1xuICAgIHAzMiArPSB5O1xuXG4gICAgLy8gRHJhd1xuICAgIGNhbnZhcy5maWxsUG9seWdvbihuZXcgQXJyYXkocDExLCBwMjEsIHAzMSksIG5ldyBBcnJheShwMTIsIHAyMiwgcDMyKSk7XG4gIH1cblxuICAvKipcbiAgICogR2V0IHRoZSBhbmd1bGFyIGNvb3JkaW5hdGUuXG4gICAqIEBwYXJhbSB4IFggY29vcmRpbmF0ZVxuICAgKiBAcGFyYW0geSBZIGNvb3JkaW5hdGVcbiAgICovXG4gICBmdW5jdGlvbiBhbmd1bGFyQ29vcmQoeCwgeSlcbiAgIHtcbiAgICAgdmFyIHBoaSA9IDAuMDtcblxuICAgICBpZiAoeCA+IDAgJiYgeSA+PSAwKSB7XG4gICAgICBwaGkgPSBNYXRoLmF0YW4oeS94KTtcbiAgICAgfVxuICAgICBpZiAoeCA+IDAgJiYgeSA8IDApIHtcbiAgICAgICBwaGkgPSBNYXRoLmF0YW4oeS94KSArIDIqTWF0aC5QSTtcbiAgICAgfVxuICAgICBpZiAoeCA8IDApIHtcbiAgICAgICBwaGkgPSBNYXRoLmF0YW4oeS94KSArIE1hdGguUEk7XG4gICAgIH1cbiAgICAgaWYgKHggPSAwICYmIHkgPiAwKSB7XG4gICAgICAgcGhpID0gTWF0aC5QSS8yO1xuICAgICB9XG4gICAgIGlmICh4ID0gMCAmJiB5IDwgMCkge1xuICAgICAgIHBoaSA9IDMqTWF0aC5QSS8yO1xuICAgICB9XG5cbiAgICAgcmV0dXJuIHBoaTtcbiAgIH1cblxuICAgLyoqXG4gICAgKiBHZXQgdGhlIHJhZGlhbiBjb29yZGlhbnRlLlxuICAgICogQHBhcmFtIHgxXG4gICAgKiBAcGFyYW0geTFcbiAgICAqIEBwYXJhbSB4MlxuICAgICogQHBhcmFtIHkyXG4gICAgKi9cbiAgIGZ1bmN0aW9uIHJhZGlhbENvb3JkKHgsIHkpXG4gICB7XG4gICAgIHJldHVybiBNYXRoLnNxcnQoeCp4ICsgeSp5KTtcbiAgIH1cbn07XG5cbi8qKlxuICogQ2FsY3VsYXRlcyB0aGUgY29vcmRpbmF0ZXMgYmFzZWQgb24gcHVyZSBjaGFuY2UuXG4gKlxuICogQHBhcmFtIGdyYXBoIEEgdmFsaWQgZ3JhcGggaW5zdGFuY2VcbiAqL1xuZm9vZ3JhcGguUmFuZG9tVmVydGV4TGF5b3V0LnByb3RvdHlwZS5sYXlvdXQgPSBmdW5jdGlvbihncmFwaCkge1xuICBmb3IgKHZhciBpID0gMDsgaTxncmFwaC52ZXJ0aWNlcy5sZW5ndGg7IGkrKykge1xuICAgIHZhciB2ID0gZ3JhcGgudmVydGljZXNbaV07XG4gICAgdi54ID0gTWF0aC5yb3VuZChNYXRoLnJhbmRvbSgpICogdGhpcy53aWR0aCk7XG4gICAgdi55ID0gTWF0aC5yb3VuZChNYXRoLnJhbmRvbSgpICogdGhpcy5oZWlnaHQpO1xuICB9XG59O1xuXG4vKipcbiAqIElkZW50aWZpZXMgY29ubmVjdGVkIGNvbXBvbmVudHMgb2YgYSBncmFwaCBhbmQgY3JlYXRlcyBcImNlbnRyYWxcIlxuICogdmVydGljZXMgZm9yIGVhY2ggY29tcG9uZW50LiBJZiB0aGVyZSBpcyBtb3JlIHRoYW4gb25lIGNvbXBvbmVudCxcbiAqIGFsbCBjZW50cmFsIHZlcnRpY2VzIG9mIGluZGl2aWR1YWwgY29tcG9uZW50cyBhcmUgY29ubmVjdGVkIHRvXG4gKiBlYWNoIG90aGVyIHRvIHByZXZlbnQgY29tcG9uZW50IGRyaWZ0LlxuICpcbiAqIEBwYXJhbSBncmFwaCBBIHZhbGlkIGdyYXBoIGluc3RhbmNlXG4gKiBAcmV0dXJuIEEgbGlzdCBvZiBjb21wb25lbnQgY2VudGVyIHZlcnRpY2VzIG9yIG51bGwgd2hlbiB0aGVyZVxuICogICAgICAgICBpcyBvbmx5IG9uZSBjb21wb25lbnQuXG4gKi9cbmZvb2dyYXBoLkZvcmNlRGlyZWN0ZWRWZXJ0ZXhMYXlvdXQucHJvdG90eXBlLl9faWRlbnRpZnlDb21wb25lbnRzID0gZnVuY3Rpb24oZ3JhcGgpIHtcbiAgdmFyIGNvbXBvbmVudENlbnRlcnMgPSBuZXcgQXJyYXkoKTtcbiAgdmFyIGNvbXBvbmVudHMgPSBuZXcgQXJyYXkoKTtcblxuICAvLyBEZXB0aCBmaXJzdCBzZWFyY2hcbiAgZnVuY3Rpb24gZGZzKHZlcnRleClcbiAge1xuICAgIHZhciBzdGFjayA9IG5ldyBBcnJheSgpO1xuICAgIHZhciBjb21wb25lbnQgPSBuZXcgQXJyYXkoKTtcbiAgICB2YXIgY2VudGVyVmVydGV4ID0gbmV3IGZvb2dyYXBoLlZlcnRleChcImNvbXBvbmVudF9jZW50ZXJcIiwgLTEsIC0xKTtcbiAgICBjZW50ZXJWZXJ0ZXguaGlkZGVuID0gdHJ1ZTtcbiAgICBjb21wb25lbnRDZW50ZXJzLnB1c2goY2VudGVyVmVydGV4KTtcbiAgICBjb21wb25lbnRzLnB1c2goY29tcG9uZW50KTtcblxuICAgIGZ1bmN0aW9uIHZpc2l0VmVydGV4KHYpXG4gICAge1xuICAgICAgY29tcG9uZW50LnB1c2godik7XG4gICAgICB2Ll9fZGZzVmlzaXRlZCA9IHRydWU7XG5cbiAgICAgIGZvciAodmFyIGkgaW4gdi5lZGdlcykge1xuICAgICAgICB2YXIgZSA9IHYuZWRnZXNbaV07XG4gICAgICAgIGlmICghZS5oaWRkZW4pXG4gICAgICAgICAgc3RhY2sucHVzaChlLmVuZFZlcnRleCk7XG4gICAgICB9XG5cbiAgICAgIGZvciAodmFyIGkgaW4gdi5yZXZlcnNlRWRnZXMpIHtcbiAgICAgICAgaWYgKCF2LnJldmVyc2VFZGdlc1tpXS5oaWRkZW4pXG4gICAgICAgICAgc3RhY2sucHVzaCh2LnJldmVyc2VFZGdlc1tpXS5lbmRWZXJ0ZXgpO1xuICAgICAgfVxuICAgIH1cblxuICAgIHZpc2l0VmVydGV4KHZlcnRleCk7XG4gICAgd2hpbGUgKHN0YWNrLmxlbmd0aCA+IDApIHtcbiAgICAgIHZhciB1ID0gc3RhY2sucG9wKCk7XG5cbiAgICAgIGlmICghdS5fX2Rmc1Zpc2l0ZWQgJiYgIXUuaGlkZGVuKSB7XG4gICAgICAgIHZpc2l0VmVydGV4KHUpO1xuICAgICAgfVxuICAgIH1cbiAgfVxuXG4gIC8vIENsZWFyIERGUyB2aXNpdGVkIGZsYWdcbiAgZm9yICh2YXIgaSBpbiBncmFwaC52ZXJ0aWNlcykge1xuICAgIHZhciB2ID0gZ3JhcGgudmVydGljZXNbaV07XG4gICAgdi5fX2Rmc1Zpc2l0ZWQgPSBmYWxzZTtcbiAgfVxuXG4gIC8vIEl0ZXJhdGUgdGhyb3VnaCBhbGwgdmVydGljZXMgc3RhcnRpbmcgREZTIGZyb20gZWFjaCB2ZXJ0ZXhcbiAgLy8gdGhhdCBoYXNuJ3QgYmVlbiB2aXNpdGVkIHlldC5cbiAgZm9yICh2YXIgayBpbiBncmFwaC52ZXJ0aWNlcykge1xuICAgIHZhciB2ID0gZ3JhcGgudmVydGljZXNba107XG4gICAgaWYgKCF2Ll9fZGZzVmlzaXRlZCAmJiAhdi5oaWRkZW4pXG4gICAgICBkZnModik7XG4gIH1cblxuICAvLyBJbnRlcmNvbm5lY3QgYWxsIGNlbnRlciB2ZXJ0aWNlc1xuICBpZiAoY29tcG9uZW50Q2VudGVycy5sZW5ndGggPiAxKSB7XG4gICAgZm9yICh2YXIgaSBpbiBjb21wb25lbnRDZW50ZXJzKSB7XG4gICAgICBncmFwaC5pbnNlcnRWZXJ0ZXgoY29tcG9uZW50Q2VudGVyc1tpXSk7XG4gICAgfVxuICAgIGZvciAodmFyIGkgaW4gY29tcG9uZW50cykge1xuICAgICAgZm9yICh2YXIgaiBpbiBjb21wb25lbnRzW2ldKSB7XG4gICAgICAgIC8vIENvbm5lY3QgdmlzaXRlZCB2ZXJ0ZXggdG8gXCJjZW50cmFsXCIgY29tcG9uZW50IHZlcnRleFxuICAgICAgICBlZGdlID0gZ3JhcGguaW5zZXJ0RWRnZShcIlwiLCAxLCBjb21wb25lbnRzW2ldW2pdLCBjb21wb25lbnRDZW50ZXJzW2ldKTtcbiAgICAgICAgZWRnZS5oaWRkZW4gPSB0cnVlO1xuICAgICAgfVxuICAgIH1cblxuICAgIGZvciAodmFyIGkgaW4gY29tcG9uZW50Q2VudGVycykge1xuICAgICAgZm9yICh2YXIgaiBpbiBjb21wb25lbnRDZW50ZXJzKSB7XG4gICAgICAgIGlmIChpICE9IGopIHtcbiAgICAgICAgICBlID0gZ3JhcGguaW5zZXJ0RWRnZShcIlwiLCAzLCBjb21wb25lbnRDZW50ZXJzW2ldLCBjb21wb25lbnRDZW50ZXJzW2pdKTtcbiAgICAgICAgICBlLmhpZGRlbiA9IHRydWU7XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG5cbiAgICByZXR1cm4gY29tcG9uZW50Q2VudGVycztcbiAgfVxuXG4gIHJldHVybiBudWxsO1xufTtcblxuLyoqXG4gKiBDYWxjdWxhdGVzIHRoZSBjb29yZGluYXRlcyBiYXNlZCBvbiBmb3JjZS1kaXJlY3RlZCBwbGFjZW1lbnRcbiAqIGFsZ29yaXRobS5cbiAqXG4gKiBAcGFyYW0gZ3JhcGggQSB2YWxpZCBncmFwaCBpbnN0YW5jZVxuICovXG5mb29ncmFwaC5Gb3JjZURpcmVjdGVkVmVydGV4TGF5b3V0LnByb3RvdHlwZS5sYXlvdXQgPSBmdW5jdGlvbihncmFwaCkge1xuICB0aGlzLmdyYXBoID0gZ3JhcGg7XG4gIHZhciBhcmVhID0gdGhpcy53aWR0aCAqIHRoaXMuaGVpZ2h0O1xuICB2YXIgayA9IE1hdGguc3FydChhcmVhIC8gZ3JhcGgudmVydGV4Q291bnQpO1xuXG4gIHZhciB0ID0gdGhpcy53aWR0aCAvIDEwOyAvLyBUZW1wZXJhdHVyZS5cbiAgdmFyIGR0ID0gdCAvICh0aGlzLml0ZXJhdGlvbnMgKyAxKTtcblxuICB2YXIgZXBzID0gdGhpcy5lcHM7IC8vIE1pbmltdW0gZGlzdGFuY2UgYmV0d2VlbiB0aGUgdmVydGljZXNcblxuICAvLyBBdHRyYWN0aXZlIGFuZCByZXB1bHNpdmUgZm9yY2VzXG4gIGZ1bmN0aW9uIEZhKHopIHsgcmV0dXJuIGZvb2dyYXBoLkEqeip6L2s7IH1cbiAgZnVuY3Rpb24gRnIoeikgeyByZXR1cm4gZm9vZ3JhcGguUiprKmsvejsgfVxuICBmdW5jdGlvbiBGdyh6KSB7IHJldHVybiAxL3oqejsgfSAgLy8gRm9yY2UgZW1pdGVkIGJ5IHRoZSB3YWxsc1xuXG4gIC8vIEluaXRpYXRlIGNvbXBvbmVudCBpZGVudGlmaWNhdGlvbiBhbmQgdmlydHVhbCB2ZXJ0ZXggY3JlYXRpb25cbiAgLy8gdG8gcHJldmVudCBkaXNjb25uZWN0ZWQgZ3JhcGggY29tcG9uZW50cyBmcm9tIGRyaWZ0aW5nIHRvbyBmYXIgYXBhcnRcbiAgY2VudGVycyA9IHRoaXMuX19pZGVudGlmeUNvbXBvbmVudHMoZ3JhcGgpO1xuXG4gIC8vIEFzc2lnbiBpbml0aWFsIHJhbmRvbSBwb3NpdGlvbnNcbiAgaWYodGhpcy5yYW5kb21pemUpIHtcbiAgICByYW5kb21MYXlvdXQgPSBuZXcgZm9vZ3JhcGguUmFuZG9tVmVydGV4TGF5b3V0KHRoaXMud2lkdGgsIHRoaXMuaGVpZ2h0KTtcbiAgICByYW5kb21MYXlvdXQubGF5b3V0KGdyYXBoKTtcbiAgfVxuXG4gIC8vIFJ1biB0aHJvdWdoIHNvbWUgaXRlcmF0aW9uc1xuICBmb3IgKHZhciBxID0gMDsgcSA8IHRoaXMuaXRlcmF0aW9uczsgcSsrKSB7XG5cbiAgICAvKiBDYWxjdWxhdGUgcmVwdWxzaXZlIGZvcmNlcy4gKi9cbiAgICBmb3IgKHZhciBpMSBpbiBncmFwaC52ZXJ0aWNlcykge1xuICAgICAgdmFyIHYgPSBncmFwaC52ZXJ0aWNlc1tpMV07XG5cbiAgICAgIHYuZHggPSAwO1xuICAgICAgdi5keSA9IDA7XG4gICAgICAvLyBEbyBub3QgbW92ZSBmaXhlZCB2ZXJ0aWNlc1xuICAgICAgaWYoIXYuZml4ZWQpIHtcbiAgICAgICAgZm9yICh2YXIgaTIgaW4gZ3JhcGgudmVydGljZXMpIHtcbiAgICAgICAgICB2YXIgdSA9IGdyYXBoLnZlcnRpY2VzW2kyXTtcbiAgICAgICAgICBpZiAodiAhPSB1ICYmICF1LmZpeGVkKSB7XG4gICAgICAgICAgICAvKiBEaWZmZXJlbmNlIHZlY3RvciBiZXR3ZWVuIHRoZSB0d28gdmVydGljZXMuICovXG4gICAgICAgICAgICB2YXIgZGlmeCA9IHYueCAtIHUueDtcbiAgICAgICAgICAgIHZhciBkaWZ5ID0gdi55IC0gdS55O1xuXG4gICAgICAgICAgICAvKiBMZW5ndGggb2YgdGhlIGRpZiB2ZWN0b3IuICovXG4gICAgICAgICAgICB2YXIgZCA9IE1hdGgubWF4KGVwcywgTWF0aC5zcXJ0KGRpZngqZGlmeCArIGRpZnkqZGlmeSkpO1xuICAgICAgICAgICAgdmFyIGZvcmNlID0gRnIoZCk7XG4gICAgICAgICAgICB2LmR4ID0gdi5keCArIChkaWZ4L2QpICogZm9yY2U7XG4gICAgICAgICAgICB2LmR5ID0gdi5keSArIChkaWZ5L2QpICogZm9yY2U7XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICAgIC8qIFRyZWF0IHRoZSB3YWxscyBhcyBzdGF0aWMgb2JqZWN0cyBlbWl0aW5nIGZvcmNlIEZ3LiAqL1xuICAgICAgICAvLyBDYWxjdWxhdGUgdGhlIHN1bSBvZiBcIndhbGxcIiBmb3JjZXMgaW4gKHYueCwgdi55KVxuICAgICAgICAvKlxuICAgICAgICB2YXIgeCA9IE1hdGgubWF4KGVwcywgdi54KTtcbiAgICAgICAgdmFyIHkgPSBNYXRoLm1heChlcHMsIHYueSk7XG4gICAgICAgIHZhciB3eCA9IE1hdGgubWF4KGVwcywgdGhpcy53aWR0aCAtIHYueCk7XG4gICAgICAgIHZhciB3eSA9IE1hdGgubWF4KGVwcywgdGhpcy5oZWlnaHQgLSB2LnkpOyAgIC8vIEdvdHRhIGxvdmUgYWxsIHRob3NlIE5hTidzIDopXG4gICAgICAgIHZhciBSeCA9IEZ3KHgpIC0gRncod3gpO1xuICAgICAgICB2YXIgUnkgPSBGdyh5KSAtIEZ3KHd5KTtcblxuICAgICAgICB2LmR4ID0gdi5keCArIFJ4O1xuICAgICAgICB2LmR5ID0gdi5keSArIFJ5O1xuICAgICAgICAqL1xuICAgICAgfVxuICAgIH1cblxuICAgIC8qIENhbGN1bGF0ZSBhdHRyYWN0aXZlIGZvcmNlcy4gKi9cbiAgICBmb3IgKHZhciBpMyBpbiBncmFwaC52ZXJ0aWNlcykge1xuICAgICAgdmFyIHYgPSBncmFwaC52ZXJ0aWNlc1tpM107XG5cbiAgICAgIC8vIERvIG5vdCBtb3ZlIGZpeGVkIHZlcnRpY2VzXG4gICAgICBpZighdi5maXhlZCkge1xuICAgICAgICBmb3IgKHZhciBpNCBpbiB2LmVkZ2VzKSB7XG4gICAgICAgICAgdmFyIGUgPSB2LmVkZ2VzW2k0XTtcbiAgICAgICAgICB2YXIgdSA9IGUuZW5kVmVydGV4O1xuICAgICAgICAgIHZhciBkaWZ4ID0gdi54IC0gdS54O1xuICAgICAgICAgIHZhciBkaWZ5ID0gdi55IC0gdS55O1xuICAgICAgICAgIHZhciBkID0gTWF0aC5tYXgoZXBzLCBNYXRoLnNxcnQoZGlmeCpkaWZ4ICsgZGlmeSpkaWZ5KSk7XG4gICAgICAgICAgdmFyIGZvcmNlID0gRmEoZCk7XG5cbiAgICAgICAgICAvKiBMZW5ndGggb2YgdGhlIGRpZiB2ZWN0b3IuICovXG4gICAgICAgICAgdmFyIGQgPSBNYXRoLm1heChlcHMsIE1hdGguc3FydChkaWZ4KmRpZnggKyBkaWZ5KmRpZnkpKTtcbiAgICAgICAgICB2LmR4ID0gdi5keCAtIChkaWZ4L2QpICogZm9yY2U7XG4gICAgICAgICAgdi5keSA9IHYuZHkgLSAoZGlmeS9kKSAqIGZvcmNlO1xuXG4gICAgICAgICAgdS5keCA9IHUuZHggKyAoZGlmeC9kKSAqIGZvcmNlO1xuICAgICAgICAgIHUuZHkgPSB1LmR5ICsgKGRpZnkvZCkgKiBmb3JjZTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cblxuICAgIC8qIExpbWl0IHRoZSBtYXhpbXVtIGRpc3BsYWNlbWVudCB0byB0aGUgdGVtcGVyYXR1cmUgdFxuICAgICAgICBhbmQgcHJldmVudCBmcm9tIGJlaW5nIGRpc3BsYWNlZCBvdXRzaWRlIGZyYW1lLiAgICAgKi9cbiAgICBmb3IgKHZhciBpNSBpbiBncmFwaC52ZXJ0aWNlcykge1xuICAgICAgdmFyIHYgPSBncmFwaC52ZXJ0aWNlc1tpNV07XG4gICAgICBpZighdi5maXhlZCkge1xuICAgICAgICAvKiBMZW5ndGggb2YgdGhlIGRpc3BsYWNlbWVudCB2ZWN0b3IuICovXG4gICAgICAgIHZhciBkID0gTWF0aC5tYXgoZXBzLCBNYXRoLnNxcnQodi5keCp2LmR4ICsgdi5keSp2LmR5KSk7XG5cbiAgICAgICAgLyogTGltaXQgdG8gdGhlIHRlbXBlcmF0dXJlIHQuICovXG4gICAgICAgIHYueCA9IHYueCArICh2LmR4L2QpICogTWF0aC5taW4oZCwgdCk7XG4gICAgICAgIHYueSA9IHYueSArICh2LmR5L2QpICogTWF0aC5taW4oZCwgdCk7XG5cbiAgICAgICAgLyogU3RheSBpbnNpZGUgdGhlIGZyYW1lLiAqL1xuICAgICAgICAvKlxuICAgICAgICBib3JkZXJXaWR0aCA9IHRoaXMud2lkdGggLyA1MDtcbiAgICAgICAgaWYgKHYueCA8IGJvcmRlcldpZHRoKSB7XG4gICAgICAgICAgdi54ID0gYm9yZGVyV2lkdGg7XG4gICAgICAgIH0gZWxzZSBpZiAodi54ID4gdGhpcy53aWR0aCAtIGJvcmRlcldpZHRoKSB7XG4gICAgICAgICAgdi54ID0gdGhpcy53aWR0aCAtIGJvcmRlcldpZHRoO1xuICAgICAgICB9XG5cbiAgICAgICAgaWYgKHYueSA8IGJvcmRlcldpZHRoKSB7XG4gICAgICAgICAgdi55ID0gYm9yZGVyV2lkdGg7XG4gICAgICAgIH0gZWxzZSBpZiAodi55ID4gdGhpcy5oZWlnaHQgLSBib3JkZXJXaWR0aCkge1xuICAgICAgICAgIHYueSA9IHRoaXMuaGVpZ2h0IC0gYm9yZGVyV2lkdGg7XG4gICAgICAgIH1cbiAgICAgICAgKi9cbiAgICAgICAgdi54ID0gTWF0aC5yb3VuZCh2LngpO1xuICAgICAgICB2LnkgPSBNYXRoLnJvdW5kKHYueSk7XG4gICAgICB9XG4gICAgfVxuXG4gICAgLyogQ29vbC4gKi9cbiAgICB0IC09IGR0O1xuXG4gICAgaWYgKHEgJSAxMCA9PSAwKSB7XG4gICAgICB0aGlzLmNhbGxiYWNrKCk7XG4gICAgfVxuICB9XG5cbiAgLy8gUmVtb3ZlIHZpcnR1YWwgY2VudGVyIHZlcnRpY2VzXG4gIGlmIChjZW50ZXJzKSB7XG4gICAgZm9yICh2YXIgaSBpbiBjZW50ZXJzKSB7XG4gICAgICBncmFwaC5yZW1vdmVWZXJ0ZXgoY2VudGVyc1tpXSk7XG4gICAgfVxuICB9XG5cbiAgZ3JhcGgubm9ybWFsaXplKHRoaXMud2lkdGgsIHRoaXMuaGVpZ2h0LCB0cnVlKTtcbn07XG5cbm1vZHVsZS5leHBvcnRzID0gZm9vZ3JhcGg7XG4iLCIndXNlIHN0cmljdCc7XG5cbihmdW5jdGlvbigpe1xuXG4gIC8vIHJlZ2lzdGVycyB0aGUgZXh0ZW5zaW9uIG9uIGEgY3l0b3NjYXBlIGxpYiByZWZcbiAgdmFyIGdldExheW91dCA9IHJlcXVpcmUoJy4vbGF5b3V0Jyk7XG4gIHZhciByZWdpc3RlciA9IGZ1bmN0aW9uKCBjeXRvc2NhcGUgKXtcbiAgICB2YXIgbGF5b3V0ID0gZ2V0TGF5b3V0KCBjeXRvc2NhcGUgKTtcblxuICAgIGN5dG9zY2FwZSgnbGF5b3V0JywgJ3NwcmVhZCcsIGxheW91dCk7XG4gIH07XG5cbiAgaWYoIHR5cGVvZiBtb2R1bGUgIT09ICd1bmRlZmluZWQnICYmIG1vZHVsZS5leHBvcnRzICl7IC8vIGV4cG9zZSBhcyBhIGNvbW1vbmpzIG1vZHVsZVxuICAgIG1vZHVsZS5leHBvcnRzID0gcmVnaXN0ZXI7XG4gIH1cblxuICBpZiggdHlwZW9mIGRlZmluZSAhPT0gJ3VuZGVmaW5lZCcgJiYgZGVmaW5lLmFtZCApeyAvLyBleHBvc2UgYXMgYW4gYW1kL3JlcXVpcmVqcyBtb2R1bGVcbiAgICBkZWZpbmUoJ2N5dG9zY2FwZS1zcHJlYWQnLCBmdW5jdGlvbigpe1xuICAgICAgcmV0dXJuIHJlZ2lzdGVyO1xuICAgIH0pO1xuICB9XG5cbiAgaWYoIHR5cGVvZiBjeXRvc2NhcGUgIT09ICd1bmRlZmluZWQnICl7IC8vIGV4cG9zZSB0byBnbG9iYWwgY3l0b3NjYXBlIChpLmUuIHdpbmRvdy5jeXRvc2NhcGUpXG4gICAgcmVnaXN0ZXIoIGN5dG9zY2FwZSApO1xuICB9XG5cbn0pKCk7XG4iLCJ2YXIgVGhyZWFkO1xuXG52YXIgZm9vZ3JhcGggPSByZXF1aXJlKCcuL2Zvb2dyYXBoJyk7XG52YXIgVm9yb25vaSA9IHJlcXVpcmUoJy4vcmhpbGwtdm9yb25vaS1jb3JlJyk7XG5cbi8qXG4gKiBUaGlzIGxheW91dCBjb21iaW5lcyBzZXZlcmFsIGFsZ29yaXRobXM6XG4gKlxuICogLSBJdCBnZW5lcmF0ZXMgYW4gaW5pdGlhbCBwb3NpdGlvbiBvZiB0aGUgbm9kZXMgYnkgdXNpbmcgdGhlXG4gKiAgIEZydWNodGVybWFuLVJlaW5nb2xkIGFsZ29yaXRobSAoZG9pOjEwLjEwMDIvc3BlLjQzODAyMTExMDIpXG4gKlxuICogLSBGaW5hbGx5IGl0IGVsaW1pbmF0ZXMgb3ZlcmxhcHMgYnkgdXNpbmcgdGhlIG1ldGhvZCBkZXNjcmliZWQgYnlcbiAqICAgR2Fuc25lciBhbmQgTm9ydGggKGRvaToxMC4xMDA3LzMtNTQwLTM3NjIzLTJfMjgpXG4gKi9cblxudmFyIGRlZmF1bHRzID0ge1xuICBhbmltYXRlOiB0cnVlLCAvLyB3aGV0aGVyIHRvIHNob3cgdGhlIGxheW91dCBhcyBpdCdzIHJ1bm5pbmdcbiAgcmVhZHk6IHVuZGVmaW5lZCwgLy8gQ2FsbGJhY2sgb24gbGF5b3V0cmVhZHlcbiAgc3RvcDogdW5kZWZpbmVkLCAvLyBDYWxsYmFjayBvbiBsYXlvdXRzdG9wXG4gIGZpdDogdHJ1ZSwgLy8gUmVzZXQgdmlld3BvcnQgdG8gZml0IGRlZmF1bHQgc2ltdWxhdGlvbkJvdW5kc1xuICBtaW5EaXN0OiAyMCwgLy8gTWluaW11bSBkaXN0YW5jZSBiZXR3ZWVuIG5vZGVzXG4gIHBhZGRpbmc6IDIwLCAvLyBQYWRkaW5nXG4gIGV4cGFuZGluZ0ZhY3RvcjogLTEuMCwgLy8gSWYgdGhlIG5ldHdvcmsgZG9lcyBub3Qgc2F0aXNmeSB0aGUgbWluRGlzdFxuICAvLyBjcml0ZXJpdW0gdGhlbiBpdCBleHBhbmRzIHRoZSBuZXR3b3JrIG9mIHRoaXMgYW1vdW50XG4gIC8vIElmIGl0IGlzIHNldCB0byAtMS4wIHRoZSBhbW91bnQgb2YgZXhwYW5zaW9uIGlzIGF1dG9tYXRpY2FsbHlcbiAgLy8gY2FsY3VsYXRlZCBiYXNlZCBvbiB0aGUgbWluRGlzdCwgdGhlIGFzcGVjdCByYXRpbyBhbmQgdGhlXG4gIC8vIG51bWJlciBvZiBub2Rlc1xuICBtYXhGcnVjaHRlcm1hblJlaW5nb2xkSXRlcmF0aW9uczogNTAsIC8vIE1heGltdW0gbnVtYmVyIG9mIGluaXRpYWwgZm9yY2UtZGlyZWN0ZWQgaXRlcmF0aW9uc1xuICBtYXhFeHBhbmRJdGVyYXRpb25zOiA0LCAvLyBNYXhpbXVtIG51bWJlciBvZiBleHBhbmRpbmcgaXRlcmF0aW9uc1xuICBib3VuZGluZ0JveDogdW5kZWZpbmVkLCAvLyBDb25zdHJhaW4gbGF5b3V0IGJvdW5kczsgeyB4MSwgeTEsIHgyLCB5MiB9IG9yIHsgeDEsIHkxLCB3LCBoIH1cbiAgcmFuZG9taXplOiBmYWxzZSAvLyB1c2VzIHJhbmRvbSBpbml0aWFsIG5vZGUgcG9zaXRpb25zIG9uIHRydWVcbn07XG5cbmZ1bmN0aW9uIFNwcmVhZExheW91dCggb3B0aW9ucyApIHtcbiAgdmFyIG9wdHMgPSB0aGlzLm9wdGlvbnMgPSB7fTtcbiAgZm9yKCB2YXIgaSBpbiBkZWZhdWx0cyApeyBvcHRzW2ldID0gZGVmYXVsdHNbaV07IH1cbiAgZm9yKCB2YXIgaSBpbiBvcHRpb25zICl7IG9wdHNbaV0gPSBvcHRpb25zW2ldOyB9XG59XG5cblNwcmVhZExheW91dC5wcm90b3R5cGUucnVuID0gZnVuY3Rpb24oKSB7XG5cbiAgdmFyIGxheW91dCA9IHRoaXM7XG4gIHZhciBvcHRpb25zID0gdGhpcy5vcHRpb25zO1xuICB2YXIgY3kgPSBvcHRpb25zLmN5O1xuXG4gIHZhciBiYiA9IG9wdGlvbnMuYm91bmRpbmdCb3ggfHwgeyB4MTogMCwgeTE6IDAsIHc6IGN5LndpZHRoKCksIGg6IGN5LmhlaWdodCgpIH07XG4gIGlmKCBiYi54MiA9PT0gdW5kZWZpbmVkICl7IGJiLngyID0gYmIueDEgKyBiYi53OyB9XG4gIGlmKCBiYi53ID09PSB1bmRlZmluZWQgKXsgYmIudyA9IGJiLngyIC0gYmIueDE7IH1cbiAgaWYoIGJiLnkyID09PSB1bmRlZmluZWQgKXsgYmIueTIgPSBiYi55MSArIGJiLmg7IH1cbiAgaWYoIGJiLmggPT09IHVuZGVmaW5lZCApeyBiYi5oID0gYmIueTIgLSBiYi55MTsgfVxuXG4gIHZhciBub2RlcyA9IGN5Lm5vZGVzKCk7XG4gIHZhciBlZGdlcyA9IGN5LmVkZ2VzKCk7XG4gIHZhciBjV2lkdGggPSBjeS53aWR0aCgpO1xuICB2YXIgY0hlaWdodCA9IGN5LmhlaWdodCgpO1xuICB2YXIgc2ltdWxhdGlvbkJvdW5kcyA9IGJiO1xuICB2YXIgcGFkZGluZyA9IG9wdGlvbnMucGFkZGluZztcbiAgdmFyIHNpbUJCRmFjdG9yID0gTWF0aC5tYXgoIDEsIE1hdGgubG9nKG5vZGVzLmxlbmd0aCkgKiAwLjggKTtcblxuICBpZiggbm9kZXMubGVuZ3RoIDwgMTAwICl7XG4gICAgc2ltQkJGYWN0b3IgLz0gMjtcbiAgfVxuXG4gIGxheW91dC50cmlnZ2VyKCB7XG4gICAgdHlwZTogJ2xheW91dHN0YXJ0JyxcbiAgICBsYXlvdXQ6IGxheW91dFxuICB9ICk7XG5cbiAgdmFyIHNpbUJCID0ge1xuICAgIHgxOiAwLFxuICAgIHkxOiAwLFxuICAgIHgyOiBjV2lkdGggKiBzaW1CQkZhY3RvcixcbiAgICB5MjogY0hlaWdodCAqIHNpbUJCRmFjdG9yXG4gIH07XG5cbiAgaWYoIHNpbXVsYXRpb25Cb3VuZHMgKSB7XG4gICAgc2ltQkIueDEgPSBzaW11bGF0aW9uQm91bmRzLngxO1xuICAgIHNpbUJCLnkxID0gc2ltdWxhdGlvbkJvdW5kcy55MTtcbiAgICBzaW1CQi54MiA9IHNpbXVsYXRpb25Cb3VuZHMueDI7XG4gICAgc2ltQkIueTIgPSBzaW11bGF0aW9uQm91bmRzLnkyO1xuICB9XG5cbiAgc2ltQkIueDEgKz0gcGFkZGluZztcbiAgc2ltQkIueTEgKz0gcGFkZGluZztcbiAgc2ltQkIueDIgLT0gcGFkZGluZztcbiAgc2ltQkIueTIgLT0gcGFkZGluZztcblxuICB2YXIgd2lkdGggPSBzaW1CQi54MiAtIHNpbUJCLngxO1xuICB2YXIgaGVpZ2h0ID0gc2ltQkIueTIgLSBzaW1CQi55MTtcblxuICAvLyBHZXQgc3RhcnQgdGltZVxuICB2YXIgc3RhcnRUaW1lID0gRGF0ZS5ub3coKTtcblxuICAvLyBsYXlvdXQgZG9lc24ndCB3b3JrIHdpdGgganVzdCAxIG5vZGVcbiAgaWYoIG5vZGVzLnNpemUoKSA8PSAxICkge1xuICAgIG5vZGVzLnBvc2l0aW9ucygge1xuICAgICAgeDogTWF0aC5yb3VuZCggKCBzaW1CQi54MSArIHNpbUJCLngyICkgLyAyICksXG4gICAgICB5OiBNYXRoLnJvdW5kKCAoIHNpbUJCLnkxICsgc2ltQkIueTIgKSAvIDIgKVxuICAgIH0gKTtcblxuICAgIGlmKCBvcHRpb25zLmZpdCApIHtcbiAgICAgIGN5LmZpdCggb3B0aW9ucy5wYWRkaW5nICk7XG4gICAgfVxuXG4gICAgLy8gR2V0IGVuZCB0aW1lXG4gICAgdmFyIGVuZFRpbWUgPSBEYXRlLm5vdygpO1xuICAgIGNvbnNvbGUuaW5mbyggXCJMYXlvdXQgb24gXCIgKyBub2Rlcy5zaXplKCkgKyBcIiBub2RlcyB0b29rIFwiICsgKCBlbmRUaW1lIC0gc3RhcnRUaW1lICkgKyBcIiBtc1wiICk7XG5cbiAgICBsYXlvdXQub25lKCBcImxheW91dHJlYWR5XCIsIG9wdGlvbnMucmVhZHkgKTtcbiAgICBsYXlvdXQudHJpZ2dlciggXCJsYXlvdXRyZWFkeVwiICk7XG5cbiAgICBsYXlvdXQub25lKCBcImxheW91dHN0b3BcIiwgb3B0aW9ucy5zdG9wICk7XG4gICAgbGF5b3V0LnRyaWdnZXIoIFwibGF5b3V0c3RvcFwiICk7XG5cbiAgICByZXR1cm47XG4gIH1cblxuICAvLyBGaXJzdCBJIG5lZWQgdG8gY3JlYXRlIHRoZSBkYXRhIHN0cnVjdHVyZSB0byBwYXNzIHRvIHRoZSB3b3JrZXJcbiAgdmFyIHBEYXRhID0ge1xuICAgICd3aWR0aCc6IHdpZHRoLFxuICAgICdoZWlnaHQnOiBoZWlnaHQsXG4gICAgJ21pbkRpc3QnOiBvcHRpb25zLm1pbkRpc3QsXG4gICAgJ2V4cEZhY3QnOiBvcHRpb25zLmV4cGFuZGluZ0ZhY3RvcixcbiAgICAnZXhwSXQnOiAwLFxuICAgICdtYXhFeHBJdCc6IG9wdGlvbnMubWF4RXhwYW5kSXRlcmF0aW9ucyxcbiAgICAndmVydGljZXMnOiBbXSxcbiAgICAnZWRnZXMnOiBbXSxcbiAgICAnc3RhcnRUaW1lJzogc3RhcnRUaW1lLFxuICAgICdtYXhGcnVjaHRlcm1hblJlaW5nb2xkSXRlcmF0aW9ucyc6IG9wdGlvbnMubWF4RnJ1Y2h0ZXJtYW5SZWluZ29sZEl0ZXJhdGlvbnNcbiAgfTtcblxuICBub2Rlcy5lYWNoKFxuICAgIGZ1bmN0aW9uKCBpLCBub2RlICkge1xuICAgICAgdmFyIG5vZGVJZCA9IG5vZGUuaWQoKTtcbiAgICAgIHZhciBwb3MgPSBub2RlLnBvc2l0aW9uKCk7XG5cbiAgICAgIGlmKCBvcHRpb25zLnJhbmRvbWl6ZSApe1xuICAgICAgICBwb3MgPSB7XG4gICAgICAgICAgeDogTWF0aC5yb3VuZCggc2ltQkIueDEgKyAoc2ltQkIueDIgLSBzaW1CQi54MSkgKiBNYXRoLnJhbmRvbSgpICksXG4gICAgICAgICAgeTogTWF0aC5yb3VuZCggc2ltQkIueTEgKyAoc2ltQkIueTIgLSBzaW1CQi55MSkgKiBNYXRoLnJhbmRvbSgpIClcbiAgICAgICAgfTtcbiAgICAgIH1cblxuICAgICAgcERhdGFbICd2ZXJ0aWNlcycgXS5wdXNoKCB7XG4gICAgICAgIGlkOiBub2RlSWQsXG4gICAgICAgIHg6IHBvcy54LFxuICAgICAgICB5OiBwb3MueVxuICAgICAgfSApO1xuICAgIH0gKTtcblxuICBlZGdlcy5lYWNoKFxuICAgIGZ1bmN0aW9uKCkge1xuICAgICAgdmFyIHNyY05vZGVJZCA9IHRoaXMuc291cmNlKCkuaWQoKTtcbiAgICAgIHZhciB0Z3ROb2RlSWQgPSB0aGlzLnRhcmdldCgpLmlkKCk7XG4gICAgICBwRGF0YVsgJ2VkZ2VzJyBdLnB1c2goIHtcbiAgICAgICAgc3JjOiBzcmNOb2RlSWQsXG4gICAgICAgIHRndDogdGd0Tm9kZUlkXG4gICAgICB9ICk7XG4gICAgfSApO1xuXG4gIC8vRGVjbGVyYXRpb25cbiAgdmFyIHQxID0gbGF5b3V0LnRocmVhZDtcblxuICAvLyByZXVzZSBvbGQgdGhyZWFkIGlmIHBvc3NpYmxlXG4gIGlmKCAhdDEgfHwgdDEuc3RvcHBlZCgpICl7XG4gICAgdDEgPSBsYXlvdXQudGhyZWFkID0gVGhyZWFkKCk7XG5cbiAgICAvLyBBbmQgdG8gYWRkIHRoZSByZXF1aXJlZCBzY3JpcHRzXG4gICAgLy9FWFRFUk5BTCAxXG4gICAgdDEucmVxdWlyZSggZm9vZ3JhcGgsICdmb29ncmFwaCcgKTtcbiAgICAvL0VYVEVSTkFMIDJcbiAgICB0MS5yZXF1aXJlKCBWb3Jvbm9pLCAnVm9yb25vaScgKTtcbiAgfVxuXG4gIGZ1bmN0aW9uIHNldFBvc2l0aW9ucyggcERhdGEgKXsgLy9jb25zb2xlLmxvZygnc2V0IHBvc25zJylcbiAgICAvLyBGaXJzdCB3ZSByZXRyaWV2ZSB0aGUgaW1wb3J0YW50IGRhdGFcbiAgICAvLyB2YXIgZXhwYW5kSXRlcmF0aW9uID0gcERhdGFbICdleHBJdCcgXTtcbiAgICB2YXIgZGF0YVZlcnRpY2VzID0gcERhdGFbICd2ZXJ0aWNlcycgXTtcbiAgICB2YXIgdmVydGljZXMgPSBbXTtcbiAgICBmb3IoIHZhciBpID0gMDsgaSA8IGRhdGFWZXJ0aWNlcy5sZW5ndGg7ICsraSApIHtcbiAgICAgIHZhciBkdiA9IGRhdGFWZXJ0aWNlc1sgaSBdO1xuICAgICAgdmVydGljZXNbIGR2LmlkIF0gPSB7XG4gICAgICAgIHg6IGR2LngsXG4gICAgICAgIHk6IGR2LnlcbiAgICAgIH07XG4gICAgfVxuICAgIC8qXG4gICAgICogRklOQUxMWTpcbiAgICAgKlxuICAgICAqIFdlIHBvc2l0aW9uIHRoZSBub2RlcyBiYXNlZCBvbiB0aGUgY2FsY3VsYXRpb25cbiAgICAgKi9cbiAgICBub2Rlcy5wb3NpdGlvbnMoXG4gICAgICBmdW5jdGlvbiggaSwgbm9kZSApIHtcbiAgICAgICAgdmFyIGlkID0gbm9kZS5pZCgpXG4gICAgICAgIHZhciB2ZXJ0ZXggPSB2ZXJ0aWNlc1sgaWQgXTtcblxuICAgICAgICByZXR1cm4ge1xuICAgICAgICAgIHg6IE1hdGgucm91bmQoIHNpbUJCLngxICsgdmVydGV4LnggKSxcbiAgICAgICAgICB5OiBNYXRoLnJvdW5kKCBzaW1CQi55MSArIHZlcnRleC55IClcbiAgICAgICAgfTtcbiAgICAgIH0gKTtcblxuICAgIGlmKCBvcHRpb25zLmZpdCApIHtcbiAgICAgIGN5LmZpdCggb3B0aW9ucy5wYWRkaW5nICk7XG4gICAgfVxuXG4gICAgY3kubm9kZXMoKS5ydHJpZ2dlciggXCJwb3NpdGlvblwiICk7XG4gIH1cblxuICB2YXIgZGlkTGF5b3V0UmVhZHkgPSBmYWxzZTtcbiAgdDEub24oJ21lc3NhZ2UnLCBmdW5jdGlvbihlKXtcbiAgICB2YXIgcERhdGEgPSBlLm1lc3NhZ2U7IC8vY29uc29sZS5sb2coJ21lc3NhZ2UnLCBlKVxuXG4gICAgaWYoICFvcHRpb25zLmFuaW1hdGUgKXtcbiAgICAgIHJldHVybjtcbiAgICB9XG5cbiAgICBzZXRQb3NpdGlvbnMoIHBEYXRhICk7XG5cbiAgICBpZiggIWRpZExheW91dFJlYWR5ICl7XG4gICAgICBsYXlvdXQudHJpZ2dlciggXCJsYXlvdXRyZWFkeVwiICk7XG5cbiAgICAgIGRpZExheW91dFJlYWR5ID0gdHJ1ZTtcbiAgICB9XG4gIH0pO1xuXG4gIGxheW91dC5vbmUoIFwibGF5b3V0cmVhZHlcIiwgb3B0aW9ucy5yZWFkeSApO1xuXG4gIHQxLnBhc3MoIHBEYXRhICkucnVuKCBmdW5jdGlvbiggcERhdGEgKSB7XG5cbiAgICBmdW5jdGlvbiBjZWxsQ2VudHJvaWQoIGNlbGwgKSB7XG4gICAgICB2YXIgaGVzID0gY2VsbC5oYWxmZWRnZXM7XG4gICAgICB2YXIgYXJlYSA9IDAsXG4gICAgICAgIHggPSAwLFxuICAgICAgICB5ID0gMDtcbiAgICAgIHZhciBwMSwgcDIsIGY7XG5cbiAgICAgIGZvciggdmFyIGkgPSAwOyBpIDwgaGVzLmxlbmd0aDsgKytpICkge1xuICAgICAgICBwMSA9IGhlc1sgaSBdLmdldEVuZHBvaW50KCk7XG4gICAgICAgIHAyID0gaGVzWyBpIF0uZ2V0U3RhcnRwb2ludCgpO1xuXG4gICAgICAgIGFyZWEgKz0gcDEueCAqIHAyLnk7XG4gICAgICAgIGFyZWEgLT0gcDEueSAqIHAyLng7XG5cbiAgICAgICAgZiA9IHAxLnggKiBwMi55IC0gcDIueCAqIHAxLnk7XG4gICAgICAgIHggKz0gKCBwMS54ICsgcDIueCApICogZjtcbiAgICAgICAgeSArPSAoIHAxLnkgKyBwMi55ICkgKiBmO1xuICAgICAgfVxuXG4gICAgICBhcmVhIC89IDI7XG4gICAgICBmID0gYXJlYSAqIDY7XG4gICAgICByZXR1cm4ge1xuICAgICAgICB4OiB4IC8gZixcbiAgICAgICAgeTogeSAvIGZcbiAgICAgIH07XG4gICAgfVxuXG4gICAgZnVuY3Rpb24gc2l0ZXNEaXN0YW5jZSggbHMsIHJzICkge1xuICAgICAgdmFyIGR4ID0gbHMueCAtIHJzLng7XG4gICAgICB2YXIgZHkgPSBscy55IC0gcnMueTtcbiAgICAgIHJldHVybiBNYXRoLnNxcnQoIGR4ICogZHggKyBkeSAqIGR5ICk7XG4gICAgfVxuXG4gICAgZm9vZ3JhcGggPSBldmFsKCdmb29ncmFwaCcpO1xuICAgIFZvcm9ub2kgPSBldmFsKCdWb3Jvbm9pJyk7XG5cbiAgICAvLyBJIG5lZWQgdG8gcmV0cmlldmUgdGhlIGltcG9ydGFudCBkYXRhXG4gICAgdmFyIGxXaWR0aCA9IHBEYXRhWyAnd2lkdGgnIF07XG4gICAgdmFyIGxIZWlnaHQgPSBwRGF0YVsgJ2hlaWdodCcgXTtcbiAgICB2YXIgbE1pbkRpc3QgPSBwRGF0YVsgJ21pbkRpc3QnIF07XG4gICAgdmFyIGxFeHBGYWN0ID0gcERhdGFbICdleHBGYWN0JyBdO1xuICAgIHZhciBsTWF4RXhwSXQgPSBwRGF0YVsgJ21heEV4cEl0JyBdO1xuICAgIHZhciBsTWF4RnJ1Y2h0ZXJtYW5SZWluZ29sZEl0ZXJhdGlvbnMgPSBwRGF0YVsgJ21heEZydWNodGVybWFuUmVpbmdvbGRJdGVyYXRpb25zJyBdO1xuXG4gICAgLy8gUHJlcGFyZSB0aGUgZGF0YSB0byBvdXRwdXRcbiAgICB2YXIgc2F2ZVBvc2l0aW9ucyA9IGZ1bmN0aW9uKCl7XG4gICAgICBwRGF0YVsgJ3dpZHRoJyBdID0gbFdpZHRoO1xuICAgICAgcERhdGFbICdoZWlnaHQnIF0gPSBsSGVpZ2h0O1xuICAgICAgcERhdGFbICdleHBJdCcgXSA9IGV4cGFuZEl0ZXJhdGlvbjtcbiAgICAgIHBEYXRhWyAnZXhwRmFjdCcgXSA9IGxFeHBGYWN0O1xuXG4gICAgICBwRGF0YVsgJ3ZlcnRpY2VzJyBdID0gW107XG4gICAgICBmb3IoIHZhciBpID0gMDsgaSA8IGZ2Lmxlbmd0aDsgKytpICkge1xuICAgICAgICBwRGF0YVsgJ3ZlcnRpY2VzJyBdLnB1c2goIHtcbiAgICAgICAgICBpZDogZnZbIGkgXS5sYWJlbCxcbiAgICAgICAgICB4OiBmdlsgaSBdLngsXG4gICAgICAgICAgeTogZnZbIGkgXS55XG4gICAgICAgIH0gKTtcbiAgICAgIH1cbiAgICB9O1xuXG4gICAgdmFyIG1lc3NhZ2VQb3NpdGlvbnMgPSBmdW5jdGlvbigpe1xuICAgICAgYnJvYWRjYXN0KCBwRGF0YSApO1xuICAgIH07XG5cbiAgICAvKlxuICAgICAqIEZJUlNUIFNURVA6IEFwcGxpY2F0aW9uIG9mIHRoZSBGcnVjaHRlcm1hbi1SZWluZ29sZCBhbGdvcml0aG1cbiAgICAgKlxuICAgICAqIFdlIHVzZSB0aGUgdmVyc2lvbiBpbXBsZW1lbnRlZCBieSB0aGUgZm9vZ3JhcGggbGlicmFyeVxuICAgICAqXG4gICAgICogUmVmLjogaHR0cHM6Ly9jb2RlLmdvb2dsZS5jb20vcC9mb29ncmFwaC9cbiAgICAgKi9cblxuICAgIC8vIFdlIG5lZWQgdG8gY3JlYXRlIGFuIGluc3RhbmNlIG9mIGEgZ3JhcGggY29tcGF0aWJsZSB3aXRoIHRoZSBsaWJyYXJ5XG4gICAgdmFyIGZyZyA9IG5ldyBmb29ncmFwaC5HcmFwaCggXCJGUmdyYXBoXCIsIGZhbHNlICk7XG5cbiAgICB2YXIgZnJnTm9kZXMgPSB7fTtcblxuICAgIC8vIFRoZW4gd2UgaGF2ZSB0byBhZGQgdGhlIHZlcnRpY2VzXG4gICAgdmFyIGRhdGFWZXJ0aWNlcyA9IHBEYXRhWyAndmVydGljZXMnIF07XG4gICAgZm9yKCB2YXIgbmkgPSAwOyBuaSA8IGRhdGFWZXJ0aWNlcy5sZW5ndGg7ICsrbmkgKSB7XG4gICAgICB2YXIgaWQgPSBkYXRhVmVydGljZXNbIG5pIF1bICdpZCcgXTtcbiAgICAgIHZhciB2ID0gbmV3IGZvb2dyYXBoLlZlcnRleCggaWQsIE1hdGgucm91bmQoIE1hdGgucmFuZG9tKCkgKiBsSGVpZ2h0ICksIE1hdGgucm91bmQoIE1hdGgucmFuZG9tKCkgKiBsSGVpZ2h0ICkgKTtcbiAgICAgIGZyZ05vZGVzWyBpZCBdID0gdjtcbiAgICAgIGZyZy5pbnNlcnRWZXJ0ZXgoIHYgKTtcbiAgICB9XG5cbiAgICB2YXIgZGF0YUVkZ2VzID0gcERhdGFbICdlZGdlcycgXTtcbiAgICBmb3IoIHZhciBlaSA9IDA7IGVpIDwgZGF0YUVkZ2VzLmxlbmd0aDsgKytlaSApIHtcbiAgICAgIHZhciBzcmNOb2RlSWQgPSBkYXRhRWRnZXNbIGVpIF1bICdzcmMnIF07XG4gICAgICB2YXIgdGd0Tm9kZUlkID0gZGF0YUVkZ2VzWyBlaSBdWyAndGd0JyBdO1xuICAgICAgZnJnLmluc2VydEVkZ2UoIFwiXCIsIDEsIGZyZ05vZGVzWyBzcmNOb2RlSWQgXSwgZnJnTm9kZXNbIHRndE5vZGVJZCBdICk7XG4gICAgfVxuXG4gICAgdmFyIGZ2ID0gZnJnLnZlcnRpY2VzO1xuXG4gICAgLy8gVGhlbiB3ZSBhcHBseSB0aGUgbGF5b3V0XG4gICAgdmFyIGl0ZXJhdGlvbnMgPSBsTWF4RnJ1Y2h0ZXJtYW5SZWluZ29sZEl0ZXJhdGlvbnM7XG4gICAgdmFyIGZyTGF5b3V0TWFuYWdlciA9IG5ldyBmb29ncmFwaC5Gb3JjZURpcmVjdGVkVmVydGV4TGF5b3V0KCBsV2lkdGgsIGxIZWlnaHQsIGl0ZXJhdGlvbnMsIGZhbHNlLCBsTWluRGlzdCApO1xuXG4gICAgZnJMYXlvdXRNYW5hZ2VyLmNhbGxiYWNrID0gZnVuY3Rpb24oKXtcbiAgICAgIHNhdmVQb3NpdGlvbnMoKTtcbiAgICAgIG1lc3NhZ2VQb3NpdGlvbnMoKTtcbiAgICB9O1xuXG4gICAgZnJMYXlvdXRNYW5hZ2VyLmxheW91dCggZnJnICk7XG5cbiAgICBzYXZlUG9zaXRpb25zKCk7XG4gICAgbWVzc2FnZVBvc2l0aW9ucygpO1xuXG4gICAgaWYoIGxNYXhFeHBJdCA8PSAwICl7XG4gICAgICByZXR1cm4gcERhdGE7XG4gICAgfVxuXG4gICAgLypcbiAgICAgKiBTRUNPTkQgU1RFUDogVGlkaW5nIHVwIG9mIHRoZSBncmFwaC5cbiAgICAgKlxuICAgICAqIFdlIHVzZSB0aGUgbWV0aG9kIGRlc2NyaWJlZCBieSBHYW5zbmVyIGFuZCBOb3J0aCwgYmFzZWQgb24gVm9yb25vaVxuICAgICAqIGRpYWdyYW1zLlxuICAgICAqXG4gICAgICogUmVmOiBkb2k6MTAuMTAwNy8zLTU0MC0zNzYyMy0yXzI4XG4gICAgICovXG5cbiAgICAvLyBXZSBjYWxjdWxhdGUgdGhlIFZvcm9ub2kgZGlhZ3JhbSBkb3IgdGhlIHBvc2l0aW9uIG9mIHRoZSBub2Rlc1xuICAgIHZhciB2b3Jvbm9pID0gbmV3IFZvcm9ub2koKTtcbiAgICB2YXIgYmJveCA9IHtcbiAgICAgIHhsOiAwLFxuICAgICAgeHI6IGxXaWR0aCxcbiAgICAgIHl0OiAwLFxuICAgICAgeWI6IGxIZWlnaHRcbiAgICB9O1xuICAgIHZhciB2U2l0ZXMgPSBbXTtcbiAgICBmb3IoIHZhciBpID0gMDsgaSA8IGZ2Lmxlbmd0aDsgKytpICkge1xuICAgICAgdlNpdGVzWyBmdlsgaSBdLmxhYmVsIF0gPSBmdlsgaSBdO1xuICAgIH1cblxuICAgIGZ1bmN0aW9uIGNoZWNrTWluRGlzdCggZWUgKSB7XG4gICAgICB2YXIgaW5mcmFjdGlvbnMgPSAwO1xuICAgICAgLy8gVGhlbiB3ZSBjaGVjayBpZiB0aGUgbWluaW11bSBkaXN0YW5jZSBpcyBzYXRpc2ZpZWRcbiAgICAgIGZvciggdmFyIGVlaSA9IDA7IGVlaSA8IGVlLmxlbmd0aDsgKytlZWkgKSB7XG4gICAgICAgIHZhciBlID0gZWVbIGVlaSBdO1xuICAgICAgICBpZiggKCBlLmxTaXRlICE9IG51bGwgKSAmJiAoIGUuclNpdGUgIT0gbnVsbCApICYmIHNpdGVzRGlzdGFuY2UoIGUubFNpdGUsIGUuclNpdGUgKSA8IGxNaW5EaXN0ICkge1xuICAgICAgICAgICsraW5mcmFjdGlvbnM7XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICAgIHJldHVybiBpbmZyYWN0aW9ucztcbiAgICB9XG5cbiAgICB2YXIgZGlhZ3JhbSA9IHZvcm9ub2kuY29tcHV0ZSggZnYsIGJib3ggKTtcblxuICAgIC8vIFRoZW4gd2UgcmVwb3NpdGlvbiB0aGUgbm9kZXMgYXQgdGhlIGNlbnRyb2lkIG9mIHRoZWlyIFZvcm9ub2kgY2VsbHNcbiAgICB2YXIgY2VsbHMgPSBkaWFncmFtLmNlbGxzO1xuICAgIGZvciggdmFyIGkgPSAwOyBpIDwgY2VsbHMubGVuZ3RoOyArK2kgKSB7XG4gICAgICB2YXIgY2VsbCA9IGNlbGxzWyBpIF07XG4gICAgICB2YXIgc2l0ZSA9IGNlbGwuc2l0ZTtcbiAgICAgIHZhciBjZW50cm9pZCA9IGNlbGxDZW50cm9pZCggY2VsbCApO1xuICAgICAgdmFyIGN1cnJ2ID0gdlNpdGVzWyBzaXRlLmxhYmVsIF07XG4gICAgICBjdXJydi54ID0gY2VudHJvaWQueDtcbiAgICAgIGN1cnJ2LnkgPSBjZW50cm9pZC55O1xuICAgIH1cblxuICAgIGlmKCBsRXhwRmFjdCA8IDAuMCApIHtcbiAgICAgIC8vIENhbGN1bGF0ZXMgdGhlIGV4cGFuZGluZyBmYWN0b3JcbiAgICAgIGxFeHBGYWN0ID0gTWF0aC5tYXgoIDAuMDUsIE1hdGgubWluKCAwLjEwLCBsTWluRGlzdCAvIE1hdGguc3FydCggKCBsV2lkdGggKiBsSGVpZ2h0ICkgLyBmdi5sZW5ndGggKSAqIDAuNSApICk7XG4gICAgICAvL2NvbnNvbGUuaW5mbyhcIkV4cGFuZGluZyBmYWN0b3IgaXMgXCIgKyAob3B0aW9ucy5leHBhbmRpbmdGYWN0b3IgKiAxMDAuMCkgKyBcIiVcIik7XG4gICAgfVxuXG4gICAgdmFyIHByZXZJbmZyYWN0aW9ucyA9IGNoZWNrTWluRGlzdCggZGlhZ3JhbS5lZGdlcyApO1xuICAgIC8vY29uc29sZS5pbmZvKFwiSW5pdGlhbCBpbmZyYWN0aW9ucyBcIiArIHByZXZJbmZyYWN0aW9ucyk7XG5cbiAgICB2YXIgYlN0b3AgPSAoIHByZXZJbmZyYWN0aW9ucyA8PSAwICkgfHwgbE1heEV4cEl0IDw9IDA7XG5cbiAgICB2YXIgdm9yb25vaUl0ZXJhdGlvbiA9IDA7XG4gICAgdmFyIGV4cGFuZEl0ZXJhdGlvbiA9IDA7XG5cbiAgICAvLyB2YXIgaW5pdFdpZHRoID0gbFdpZHRoO1xuXG4gICAgd2hpbGUoICFiU3RvcCApIHtcbiAgICAgICsrdm9yb25vaUl0ZXJhdGlvbjtcbiAgICAgIGZvciggdmFyIGl0ID0gMDsgaXQgPD0gNDsgKytpdCApIHtcbiAgICAgICAgdm9yb25vaS5yZWN5Y2xlKCBkaWFncmFtICk7XG4gICAgICAgIGRpYWdyYW0gPSB2b3Jvbm9pLmNvbXB1dGUoIGZ2LCBiYm94ICk7XG5cbiAgICAgICAgLy8gVGhlbiB3ZSByZXBvc2l0aW9uIHRoZSBub2RlcyBhdCB0aGUgY2VudHJvaWQgb2YgdGhlaXIgVm9yb25vaSBjZWxsc1xuICAgICAgICAvLyBjZWxscyA9IGRpYWdyYW0uY2VsbHM7XG4gICAgICAgIGZvciggdmFyIGkgPSAwOyBpIDwgY2VsbHMubGVuZ3RoOyArK2kgKSB7XG4gICAgICAgICAgdmFyIGNlbGwgPSBjZWxsc1sgaSBdO1xuICAgICAgICAgIHZhciBzaXRlID0gY2VsbC5zaXRlO1xuICAgICAgICAgIHZhciBjZW50cm9pZCA9IGNlbGxDZW50cm9pZCggY2VsbCApO1xuICAgICAgICAgIHZhciBjdXJydiA9IHZTaXRlc1sgc2l0ZS5sYWJlbCBdO1xuICAgICAgICAgIGN1cnJ2LnggPSBjZW50cm9pZC54O1xuICAgICAgICAgIGN1cnJ2LnkgPSBjZW50cm9pZC55O1xuICAgICAgICB9XG4gICAgICB9XG5cbiAgICAgIHZhciBjdXJySW5mcmFjdGlvbnMgPSBjaGVja01pbkRpc3QoIGRpYWdyYW0uZWRnZXMgKTtcbiAgICAgIC8vY29uc29sZS5pbmZvKFwiQ3VycmVudCBpbmZyYWN0aW9ucyBcIiArIGN1cnJJbmZyYWN0aW9ucyk7XG5cbiAgICAgIGlmKCBjdXJySW5mcmFjdGlvbnMgPD0gMCApIHtcbiAgICAgICAgYlN0b3AgPSB0cnVlO1xuICAgICAgfSBlbHNlIHtcbiAgICAgICAgaWYoIGN1cnJJbmZyYWN0aW9ucyA+PSBwcmV2SW5mcmFjdGlvbnMgfHwgdm9yb25vaUl0ZXJhdGlvbiA+PSA0ICkge1xuICAgICAgICAgIGlmKCBleHBhbmRJdGVyYXRpb24gPj0gbE1heEV4cEl0ICkge1xuICAgICAgICAgICAgYlN0b3AgPSB0cnVlO1xuICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBsV2lkdGggKz0gbFdpZHRoICogbEV4cEZhY3Q7XG4gICAgICAgICAgICBsSGVpZ2h0ICs9IGxIZWlnaHQgKiBsRXhwRmFjdDtcbiAgICAgICAgICAgIGJib3ggPSB7XG4gICAgICAgICAgICAgIHhsOiAwLFxuICAgICAgICAgICAgICB4cjogbFdpZHRoLFxuICAgICAgICAgICAgICB5dDogMCxcbiAgICAgICAgICAgICAgeWI6IGxIZWlnaHRcbiAgICAgICAgICAgIH07XG4gICAgICAgICAgICArK2V4cGFuZEl0ZXJhdGlvbjtcbiAgICAgICAgICAgIHZvcm9ub2lJdGVyYXRpb24gPSAwO1xuICAgICAgICAgICAgLy9jb25zb2xlLmluZm8oXCJFeHBhbmRlZCB0byAoXCIrd2lkdGgrXCIsXCIraGVpZ2h0K1wiKVwiKTtcbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICAgIHByZXZJbmZyYWN0aW9ucyA9IGN1cnJJbmZyYWN0aW9ucztcblxuICAgICAgc2F2ZVBvc2l0aW9ucygpO1xuICAgICAgbWVzc2FnZVBvc2l0aW9ucygpO1xuICAgIH1cblxuICAgIHNhdmVQb3NpdGlvbnMoKTtcbiAgICByZXR1cm4gcERhdGE7XG5cbiAgfSApLnRoZW4oIGZ1bmN0aW9uKCBwRGF0YSApIHtcbiAgICAvLyB2YXIgZXhwYW5kSXRlcmF0aW9uID0gcERhdGFbICdleHBJdCcgXTtcbiAgICB2YXIgZGF0YVZlcnRpY2VzID0gcERhdGFbICd2ZXJ0aWNlcycgXTtcblxuICAgIHNldFBvc2l0aW9ucyggcERhdGEgKTtcblxuICAgIC8vIEdldCBlbmQgdGltZVxuICAgIHZhciBzdGFydFRpbWUgPSBwRGF0YVsgJ3N0YXJ0VGltZScgXTtcbiAgICB2YXIgZW5kVGltZSA9IG5ldyBEYXRlKCk7XG4gICAgY29uc29sZS5pbmZvKCBcIkxheW91dCBvbiBcIiArIGRhdGFWZXJ0aWNlcy5sZW5ndGggKyBcIiBub2RlcyB0b29rIFwiICsgKCBlbmRUaW1lIC0gc3RhcnRUaW1lICkgKyBcIiBtc1wiICk7XG5cbiAgICBsYXlvdXQub25lKCBcImxheW91dHN0b3BcIiwgb3B0aW9ucy5zdG9wICk7XG5cbiAgICBpZiggIW9wdGlvbnMuYW5pbWF0ZSApe1xuICAgICAgbGF5b3V0LnRyaWdnZXIoIFwibGF5b3V0cmVhZHlcIiApO1xuICAgIH1cblxuICAgIGxheW91dC50cmlnZ2VyKCBcImxheW91dHN0b3BcIiApO1xuXG4gICAgdDEuc3RvcCgpO1xuICB9ICk7XG5cblxuICByZXR1cm4gdGhpcztcbn07IC8vIHJ1blxuXG5TcHJlYWRMYXlvdXQucHJvdG90eXBlLnN0b3AgPSBmdW5jdGlvbigpe1xuICBpZiggdGhpcy50aHJlYWQgKXtcbiAgICB0aGlzLnRocmVhZC5zdG9wKCk7XG4gIH1cblxuICB0aGlzLnRyaWdnZXIoJ2xheW91dHN0b3AnKTtcbn07XG5cblNwcmVhZExheW91dC5wcm90b3R5cGUuZGVzdHJveSA9IGZ1bmN0aW9uKCl7XG4gIGlmKCB0aGlzLnRocmVhZCApe1xuICAgIHRoaXMudGhyZWFkLnN0b3AoKTtcbiAgfVxufTtcblxubW9kdWxlLmV4cG9ydHMgPSBmdW5jdGlvbiBnZXQoIGN5dG9zY2FwZSApe1xuICBUaHJlYWQgPSBjeXRvc2NhcGUuVGhyZWFkO1xuXG4gIHJldHVybiBTcHJlYWRMYXlvdXQ7XG59O1xuIiwiLyohXG5Db3B5cmlnaHQgKEMpIDIwMTAtMjAxMyBSYXltb25kIEhpbGw6IGh0dHBzOi8vZ2l0aHViLmNvbS9nb3JoaWxsL0phdmFzY3JpcHQtVm9yb25vaVxuTUlUIExpY2Vuc2U6IFNlZSBodHRwczovL2dpdGh1Yi5jb20vZ29yaGlsbC9KYXZhc2NyaXB0LVZvcm9ub2kvTElDRU5TRS5tZFxuKi9cbi8qXG5BdXRob3I6IFJheW1vbmQgSGlsbCAocmhpbGxAcmF5bW9uZGhpbGwubmV0KVxuQ29udHJpYnV0b3I6IEplc3NlIE1vcmdhbiAobW9yZ2FqZWxAZ21haWwuY29tKVxuRmlsZTogcmhpbGwtdm9yb25vaS1jb3JlLmpzXG5WZXJzaW9uOiAwLjk4XG5EYXRlOiBKYW51YXJ5IDIxLCAyMDEzXG5EZXNjcmlwdGlvbjogVGhpcyBpcyBteSBwZXJzb25hbCBKYXZhc2NyaXB0IGltcGxlbWVudGF0aW9uIG9mXG5TdGV2ZW4gRm9ydHVuZSdzIGFsZ29yaXRobSB0byBjb21wdXRlIFZvcm9ub2kgZGlhZ3JhbXMuXG5cbkxpY2Vuc2U6IFNlZSBodHRwczovL2dpdGh1Yi5jb20vZ29yaGlsbC9KYXZhc2NyaXB0LVZvcm9ub2kvTElDRU5TRS5tZFxuQ3JlZGl0czogU2VlIGh0dHBzOi8vZ2l0aHViLmNvbS9nb3JoaWxsL0phdmFzY3JpcHQtVm9yb25vaS9DUkVESVRTLm1kXG5IaXN0b3J5OiBTZWUgaHR0cHM6Ly9naXRodWIuY29tL2dvcmhpbGwvSmF2YXNjcmlwdC1Wb3Jvbm9pL0NIQU5HRUxPRy5tZFxuXG4jIyBVc2FnZTpcblxuICB2YXIgc2l0ZXMgPSBbe3g6MzAwLHk6MzAwfSwge3g6MTAwLHk6MTAwfSwge3g6MjAwLHk6NTAwfSwge3g6MjUwLHk6NDUwfSwge3g6NjAwLHk6MTUwfV07XG4gIC8vIHhsLCB4ciBtZWFucyB4IGxlZnQsIHggcmlnaHRcbiAgLy8geXQsIHliIG1lYW5zIHkgdG9wLCB5IGJvdHRvbVxuICB2YXIgYmJveCA9IHt4bDowLCB4cjo4MDAsIHl0OjAsIHliOjYwMH07XG4gIHZhciB2b3Jvbm9pID0gbmV3IFZvcm9ub2koKTtcbiAgLy8gcGFzcyBhbiBvYmplY3Qgd2hpY2ggZXhoaWJpdHMgeGwsIHhyLCB5dCwgeWIgcHJvcGVydGllcy4gVGhlIGJvdW5kaW5nXG4gIC8vIGJveCB3aWxsIGJlIHVzZWQgdG8gY29ubmVjdCB1bmJvdW5kIGVkZ2VzLCBhbmQgdG8gY2xvc2Ugb3BlbiBjZWxsc1xuICByZXN1bHQgPSB2b3Jvbm9pLmNvbXB1dGUoc2l0ZXMsIGJib3gpO1xuICAvLyByZW5kZXIsIGZ1cnRoZXIgYW5hbHl6ZSwgZXRjLlxuXG5SZXR1cm4gdmFsdWU6XG4gIEFuIG9iamVjdCB3aXRoIHRoZSBmb2xsb3dpbmcgcHJvcGVydGllczpcblxuICByZXN1bHQudmVydGljZXMgPSBhbiBhcnJheSBvZiB1bm9yZGVyZWQsIHVuaXF1ZSBWb3Jvbm9pLlZlcnRleCBvYmplY3RzIG1ha2luZ1xuICAgIHVwIHRoZSBWb3Jvbm9pIGRpYWdyYW0uXG4gIHJlc3VsdC5lZGdlcyA9IGFuIGFycmF5IG9mIHVub3JkZXJlZCwgdW5pcXVlIFZvcm9ub2kuRWRnZSBvYmplY3RzIG1ha2luZyB1cFxuICAgIHRoZSBWb3Jvbm9pIGRpYWdyYW0uXG4gIHJlc3VsdC5jZWxscyA9IGFuIGFycmF5IG9mIFZvcm9ub2kuQ2VsbCBvYmplY3QgbWFraW5nIHVwIHRoZSBWb3Jvbm9pIGRpYWdyYW0uXG4gICAgQSBDZWxsIG9iamVjdCBtaWdodCBoYXZlIGFuIGVtcHR5IGFycmF5IG9mIGhhbGZlZGdlcywgbWVhbmluZyBubyBWb3Jvbm9pXG4gICAgY2VsbCBjb3VsZCBiZSBjb21wdXRlZCBmb3IgYSBwYXJ0aWN1bGFyIGNlbGwuXG4gIHJlc3VsdC5leGVjVGltZSA9IHRoZSB0aW1lIGl0IHRvb2sgdG8gY29tcHV0ZSB0aGUgVm9yb25vaSBkaWFncmFtLCBpblxuICAgIG1pbGxpc2Vjb25kcy5cblxuVm9yb25vaS5WZXJ0ZXggb2JqZWN0OlxuICB4OiBUaGUgeCBwb3NpdGlvbiBvZiB0aGUgdmVydGV4LlxuICB5OiBUaGUgeSBwb3NpdGlvbiBvZiB0aGUgdmVydGV4LlxuXG5Wb3Jvbm9pLkVkZ2Ugb2JqZWN0OlxuICBsU2l0ZTogdGhlIFZvcm9ub2kgc2l0ZSBvYmplY3QgYXQgdGhlIGxlZnQgb2YgdGhpcyBWb3Jvbm9pLkVkZ2Ugb2JqZWN0LlxuICByU2l0ZTogdGhlIFZvcm9ub2kgc2l0ZSBvYmplY3QgYXQgdGhlIHJpZ2h0IG9mIHRoaXMgVm9yb25vaS5FZGdlIG9iamVjdCAoY2FuXG4gICAgYmUgbnVsbCkuXG4gIHZhOiBhbiBvYmplY3Qgd2l0aCBhbiAneCcgYW5kIGEgJ3knIHByb3BlcnR5IGRlZmluaW5nIHRoZSBzdGFydCBwb2ludFxuICAgIChyZWxhdGl2ZSB0byB0aGUgVm9yb25vaSBzaXRlIG9uIHRoZSBsZWZ0KSBvZiB0aGlzIFZvcm9ub2kuRWRnZSBvYmplY3QuXG4gIHZiOiBhbiBvYmplY3Qgd2l0aCBhbiAneCcgYW5kIGEgJ3knIHByb3BlcnR5IGRlZmluaW5nIHRoZSBlbmQgcG9pbnRcbiAgICAocmVsYXRpdmUgdG8gVm9yb25vaSBzaXRlIG9uIHRoZSBsZWZ0KSBvZiB0aGlzIFZvcm9ub2kuRWRnZSBvYmplY3QuXG5cbiAgRm9yIGVkZ2VzIHdoaWNoIGFyZSB1c2VkIHRvIGNsb3NlIG9wZW4gY2VsbHMgKHVzaW5nIHRoZSBzdXBwbGllZCBib3VuZGluZ1xuICBib3gpLCB0aGUgclNpdGUgcHJvcGVydHkgd2lsbCBiZSBudWxsLlxuXG5Wb3Jvbm9pLkNlbGwgb2JqZWN0OlxuICBzaXRlOiB0aGUgVm9yb25vaSBzaXRlIG9iamVjdCBhc3NvY2lhdGVkIHdpdGggdGhlIFZvcm9ub2kgY2VsbC5cbiAgaGFsZmVkZ2VzOiBhbiBhcnJheSBvZiBWb3Jvbm9pLkhhbGZlZGdlIG9iamVjdHMsIG9yZGVyZWQgY291bnRlcmNsb2Nrd2lzZSxcbiAgICBkZWZpbmluZyB0aGUgcG9seWdvbiBmb3IgdGhpcyBWb3Jvbm9pIGNlbGwuXG5cblZvcm9ub2kuSGFsZmVkZ2Ugb2JqZWN0OlxuICBzaXRlOiB0aGUgVm9yb25vaSBzaXRlIG9iamVjdCBvd25pbmcgdGhpcyBWb3Jvbm9pLkhhbGZlZGdlIG9iamVjdC5cbiAgZWRnZTogYSByZWZlcmVuY2UgdG8gdGhlIHVuaXF1ZSBWb3Jvbm9pLkVkZ2Ugb2JqZWN0IHVuZGVybHlpbmcgdGhpc1xuICAgIFZvcm9ub2kuSGFsZmVkZ2Ugb2JqZWN0LlxuICBnZXRTdGFydHBvaW50KCk6IGEgbWV0aG9kIHJldHVybmluZyBhbiBvYmplY3Qgd2l0aCBhbiAneCcgYW5kIGEgJ3knIHByb3BlcnR5XG4gICAgZm9yIHRoZSBzdGFydCBwb2ludCBvZiB0aGlzIGhhbGZlZGdlLiBLZWVwIGluIG1pbmQgaGFsZmVkZ2VzIGFyZSBhbHdheXNcbiAgICBjb3VudGVyY29ja3dpc2UuXG4gIGdldEVuZHBvaW50KCk6IGEgbWV0aG9kIHJldHVybmluZyBhbiBvYmplY3Qgd2l0aCBhbiAneCcgYW5kIGEgJ3knIHByb3BlcnR5XG4gICAgZm9yIHRoZSBlbmQgcG9pbnQgb2YgdGhpcyBoYWxmZWRnZS4gS2VlcCBpbiBtaW5kIGhhbGZlZGdlcyBhcmUgYWx3YXlzXG4gICAgY291bnRlcmNvY2t3aXNlLlxuXG5UT0RPOiBJZGVudGlmeSBvcHBvcnR1bml0aWVzIGZvciBwZXJmb3JtYW5jZSBpbXByb3ZlbWVudC5cblxuVE9ETzogTGV0IHRoZSB1c2VyIGNsb3NlIHRoZSBWb3Jvbm9pIGNlbGxzLCBkbyBub3QgZG8gaXQgYXV0b21hdGljYWxseS4gTm90IG9ubHkgbGV0XG4gICAgICBoaW0gY2xvc2UgdGhlIGNlbGxzLCBidXQgYWxzbyBhbGxvdyBoaW0gdG8gY2xvc2UgbW9yZSB0aGFuIG9uY2UgdXNpbmcgYSBkaWZmZXJlbnRcbiAgICAgIGJvdW5kaW5nIGJveCBmb3IgdGhlIHNhbWUgVm9yb25vaSBkaWFncmFtLlxuKi9cblxuLypnbG9iYWwgTWF0aCAqL1xuXG4vLyAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS1cblxuZnVuY3Rpb24gVm9yb25vaSgpIHtcbiAgICB0aGlzLnZlcnRpY2VzID0gbnVsbDtcbiAgICB0aGlzLmVkZ2VzID0gbnVsbDtcbiAgICB0aGlzLmNlbGxzID0gbnVsbDtcbiAgICB0aGlzLnRvUmVjeWNsZSA9IG51bGw7XG4gICAgdGhpcy5iZWFjaHNlY3Rpb25KdW5reWFyZCA9IFtdO1xuICAgIHRoaXMuY2lyY2xlRXZlbnRKdW5reWFyZCA9IFtdO1xuICAgIHRoaXMudmVydGV4SnVua3lhcmQgPSBbXTtcbiAgICB0aGlzLmVkZ2VKdW5reWFyZCA9IFtdO1xuICAgIHRoaXMuY2VsbEp1bmt5YXJkID0gW107XG4gICAgfVxuXG4vLyAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS1cblxuVm9yb25vaS5wcm90b3R5cGUucmVzZXQgPSBmdW5jdGlvbigpIHtcbiAgICBpZiAoIXRoaXMuYmVhY2hsaW5lKSB7XG4gICAgICAgIHRoaXMuYmVhY2hsaW5lID0gbmV3IHRoaXMuUkJUcmVlKCk7XG4gICAgICAgIH1cbiAgICAvLyBNb3ZlIGxlZnRvdmVyIGJlYWNoc2VjdGlvbnMgdG8gdGhlIGJlYWNoc2VjdGlvbiBqdW5reWFyZC5cbiAgICBpZiAodGhpcy5iZWFjaGxpbmUucm9vdCkge1xuICAgICAgICB2YXIgYmVhY2hzZWN0aW9uID0gdGhpcy5iZWFjaGxpbmUuZ2V0Rmlyc3QodGhpcy5iZWFjaGxpbmUucm9vdCk7XG4gICAgICAgIHdoaWxlIChiZWFjaHNlY3Rpb24pIHtcbiAgICAgICAgICAgIHRoaXMuYmVhY2hzZWN0aW9uSnVua3lhcmQucHVzaChiZWFjaHNlY3Rpb24pOyAvLyBtYXJrIGZvciByZXVzZVxuICAgICAgICAgICAgYmVhY2hzZWN0aW9uID0gYmVhY2hzZWN0aW9uLnJiTmV4dDtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgIHRoaXMuYmVhY2hsaW5lLnJvb3QgPSBudWxsO1xuICAgIGlmICghdGhpcy5jaXJjbGVFdmVudHMpIHtcbiAgICAgICAgdGhpcy5jaXJjbGVFdmVudHMgPSBuZXcgdGhpcy5SQlRyZWUoKTtcbiAgICAgICAgfVxuICAgIHRoaXMuY2lyY2xlRXZlbnRzLnJvb3QgPSB0aGlzLmZpcnN0Q2lyY2xlRXZlbnQgPSBudWxsO1xuICAgIHRoaXMudmVydGljZXMgPSBbXTtcbiAgICB0aGlzLmVkZ2VzID0gW107XG4gICAgdGhpcy5jZWxscyA9IFtdO1xuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLnNxcnQgPSBmdW5jdGlvbihuKXsgcmV0dXJuIE1hdGguc3FydChuKTsgfTtcblZvcm9ub2kucHJvdG90eXBlLmFicyA9IGZ1bmN0aW9uKG4peyByZXR1cm4gTWF0aC5hYnMobik7IH07XG5Wb3Jvbm9pLnByb3RvdHlwZS7OtSA9IFZvcm9ub2kuzrUgPSAxZS05O1xuVm9yb25vaS5wcm90b3R5cGUuaW52zrUgPSBWb3Jvbm9pLmluds61ID0gMS4wIC8gVm9yb25vaS7OtTtcblZvcm9ub2kucHJvdG90eXBlLmVxdWFsV2l0aEVwc2lsb24gPSBmdW5jdGlvbihhLGIpe3JldHVybiB0aGlzLmFicyhhLWIpPDFlLTk7fTtcblZvcm9ub2kucHJvdG90eXBlLmdyZWF0ZXJUaGFuV2l0aEVwc2lsb24gPSBmdW5jdGlvbihhLGIpe3JldHVybiBhLWI+MWUtOTt9O1xuVm9yb25vaS5wcm90b3R5cGUuZ3JlYXRlclRoYW5PckVxdWFsV2l0aEVwc2lsb24gPSBmdW5jdGlvbihhLGIpe3JldHVybiBiLWE8MWUtOTt9O1xuVm9yb25vaS5wcm90b3R5cGUubGVzc1RoYW5XaXRoRXBzaWxvbiA9IGZ1bmN0aW9uKGEsYil7cmV0dXJuIGItYT4xZS05O307XG5Wb3Jvbm9pLnByb3RvdHlwZS5sZXNzVGhhbk9yRXF1YWxXaXRoRXBzaWxvbiA9IGZ1bmN0aW9uKGEsYil7cmV0dXJuIGEtYjwxZS05O307XG5cbi8vIC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLVxuLy8gUmVkLUJsYWNrIHRyZWUgY29kZSAoYmFzZWQgb24gQyB2ZXJzaW9uIG9mIFwicmJ0cmVlXCIgYnkgRnJhbmNrIEJ1aS1IdXVcbi8vIGh0dHBzOi8vZ2l0aHViLmNvbS9mYnVpaHV1L2xpYnRyZWUvYmxvYi9tYXN0ZXIvcmIuY1xuXG5Wb3Jvbm9pLnByb3RvdHlwZS5SQlRyZWUgPSBmdW5jdGlvbigpIHtcbiAgICB0aGlzLnJvb3QgPSBudWxsO1xuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLlJCVHJlZS5wcm90b3R5cGUucmJJbnNlcnRTdWNjZXNzb3IgPSBmdW5jdGlvbihub2RlLCBzdWNjZXNzb3IpIHtcbiAgICB2YXIgcGFyZW50O1xuICAgIGlmIChub2RlKSB7XG4gICAgICAgIC8vID4+PiByaGlsbCAyMDExLTA1LTI3OiBQZXJmb3JtYW5jZTogY2FjaGUgcHJldmlvdXMvbmV4dCBub2Rlc1xuICAgICAgICBzdWNjZXNzb3IucmJQcmV2aW91cyA9IG5vZGU7XG4gICAgICAgIHN1Y2Nlc3Nvci5yYk5leHQgPSBub2RlLnJiTmV4dDtcbiAgICAgICAgaWYgKG5vZGUucmJOZXh0KSB7XG4gICAgICAgICAgICBub2RlLnJiTmV4dC5yYlByZXZpb3VzID0gc3VjY2Vzc29yO1xuICAgICAgICAgICAgfVxuICAgICAgICBub2RlLnJiTmV4dCA9IHN1Y2Nlc3NvcjtcbiAgICAgICAgLy8gPDw8XG4gICAgICAgIGlmIChub2RlLnJiUmlnaHQpIHtcbiAgICAgICAgICAgIC8vIGluLXBsYWNlIGV4cGFuc2lvbiBvZiBub2RlLnJiUmlnaHQuZ2V0Rmlyc3QoKTtcbiAgICAgICAgICAgIG5vZGUgPSBub2RlLnJiUmlnaHQ7XG4gICAgICAgICAgICB3aGlsZSAobm9kZS5yYkxlZnQpIHtub2RlID0gbm9kZS5yYkxlZnQ7fVxuICAgICAgICAgICAgbm9kZS5yYkxlZnQgPSBzdWNjZXNzb3I7XG4gICAgICAgICAgICB9XG4gICAgICAgIGVsc2Uge1xuICAgICAgICAgICAgbm9kZS5yYlJpZ2h0ID0gc3VjY2Vzc29yO1xuICAgICAgICAgICAgfVxuICAgICAgICBwYXJlbnQgPSBub2RlO1xuICAgICAgICB9XG4gICAgLy8gcmhpbGwgMjAxMS0wNi0wNzogaWYgbm9kZSBpcyBudWxsLCBzdWNjZXNzb3IgbXVzdCBiZSBpbnNlcnRlZFxuICAgIC8vIHRvIHRoZSBsZWZ0LW1vc3QgcGFydCBvZiB0aGUgdHJlZVxuICAgIGVsc2UgaWYgKHRoaXMucm9vdCkge1xuICAgICAgICBub2RlID0gdGhpcy5nZXRGaXJzdCh0aGlzLnJvb3QpO1xuICAgICAgICAvLyA+Pj4gUGVyZm9ybWFuY2U6IGNhY2hlIHByZXZpb3VzL25leHQgbm9kZXNcbiAgICAgICAgc3VjY2Vzc29yLnJiUHJldmlvdXMgPSBudWxsO1xuICAgICAgICBzdWNjZXNzb3IucmJOZXh0ID0gbm9kZTtcbiAgICAgICAgbm9kZS5yYlByZXZpb3VzID0gc3VjY2Vzc29yO1xuICAgICAgICAvLyA8PDxcbiAgICAgICAgbm9kZS5yYkxlZnQgPSBzdWNjZXNzb3I7XG4gICAgICAgIHBhcmVudCA9IG5vZGU7XG4gICAgICAgIH1cbiAgICBlbHNlIHtcbiAgICAgICAgLy8gPj4+IFBlcmZvcm1hbmNlOiBjYWNoZSBwcmV2aW91cy9uZXh0IG5vZGVzXG4gICAgICAgIHN1Y2Nlc3Nvci5yYlByZXZpb3VzID0gc3VjY2Vzc29yLnJiTmV4dCA9IG51bGw7XG4gICAgICAgIC8vIDw8PFxuICAgICAgICB0aGlzLnJvb3QgPSBzdWNjZXNzb3I7XG4gICAgICAgIHBhcmVudCA9IG51bGw7XG4gICAgICAgIH1cbiAgICBzdWNjZXNzb3IucmJMZWZ0ID0gc3VjY2Vzc29yLnJiUmlnaHQgPSBudWxsO1xuICAgIHN1Y2Nlc3Nvci5yYlBhcmVudCA9IHBhcmVudDtcbiAgICBzdWNjZXNzb3IucmJSZWQgPSB0cnVlO1xuICAgIC8vIEZpeHVwIHRoZSBtb2RpZmllZCB0cmVlIGJ5IHJlY29sb3Jpbmcgbm9kZXMgYW5kIHBlcmZvcm1pbmdcbiAgICAvLyByb3RhdGlvbnMgKDIgYXQgbW9zdCkgaGVuY2UgdGhlIHJlZC1ibGFjayB0cmVlIHByb3BlcnRpZXMgYXJlXG4gICAgLy8gcHJlc2VydmVkLlxuICAgIHZhciBncmFuZHBhLCB1bmNsZTtcbiAgICBub2RlID0gc3VjY2Vzc29yO1xuICAgIHdoaWxlIChwYXJlbnQgJiYgcGFyZW50LnJiUmVkKSB7XG4gICAgICAgIGdyYW5kcGEgPSBwYXJlbnQucmJQYXJlbnQ7XG4gICAgICAgIGlmIChwYXJlbnQgPT09IGdyYW5kcGEucmJMZWZ0KSB7XG4gICAgICAgICAgICB1bmNsZSA9IGdyYW5kcGEucmJSaWdodDtcbiAgICAgICAgICAgIGlmICh1bmNsZSAmJiB1bmNsZS5yYlJlZCkge1xuICAgICAgICAgICAgICAgIHBhcmVudC5yYlJlZCA9IHVuY2xlLnJiUmVkID0gZmFsc2U7XG4gICAgICAgICAgICAgICAgZ3JhbmRwYS5yYlJlZCA9IHRydWU7XG4gICAgICAgICAgICAgICAgbm9kZSA9IGdyYW5kcGE7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgZWxzZSB7XG4gICAgICAgICAgICAgICAgaWYgKG5vZGUgPT09IHBhcmVudC5yYlJpZ2h0KSB7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMucmJSb3RhdGVMZWZ0KHBhcmVudCk7XG4gICAgICAgICAgICAgICAgICAgIG5vZGUgPSBwYXJlbnQ7XG4gICAgICAgICAgICAgICAgICAgIHBhcmVudCA9IG5vZGUucmJQYXJlbnQ7XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBwYXJlbnQucmJSZWQgPSBmYWxzZTtcbiAgICAgICAgICAgICAgICBncmFuZHBhLnJiUmVkID0gdHJ1ZTtcbiAgICAgICAgICAgICAgICB0aGlzLnJiUm90YXRlUmlnaHQoZ3JhbmRwYSk7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfVxuICAgICAgICBlbHNlIHtcbiAgICAgICAgICAgIHVuY2xlID0gZ3JhbmRwYS5yYkxlZnQ7XG4gICAgICAgICAgICBpZiAodW5jbGUgJiYgdW5jbGUucmJSZWQpIHtcbiAgICAgICAgICAgICAgICBwYXJlbnQucmJSZWQgPSB1bmNsZS5yYlJlZCA9IGZhbHNlO1xuICAgICAgICAgICAgICAgIGdyYW5kcGEucmJSZWQgPSB0cnVlO1xuICAgICAgICAgICAgICAgIG5vZGUgPSBncmFuZHBhO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGVsc2Uge1xuICAgICAgICAgICAgICAgIGlmIChub2RlID09PSBwYXJlbnQucmJMZWZ0KSB7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMucmJSb3RhdGVSaWdodChwYXJlbnQpO1xuICAgICAgICAgICAgICAgICAgICBub2RlID0gcGFyZW50O1xuICAgICAgICAgICAgICAgICAgICBwYXJlbnQgPSBub2RlLnJiUGFyZW50O1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgcGFyZW50LnJiUmVkID0gZmFsc2U7XG4gICAgICAgICAgICAgICAgZ3JhbmRwYS5yYlJlZCA9IHRydWU7XG4gICAgICAgICAgICAgICAgdGhpcy5yYlJvdGF0ZUxlZnQoZ3JhbmRwYSk7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfVxuICAgICAgICBwYXJlbnQgPSBub2RlLnJiUGFyZW50O1xuICAgICAgICB9XG4gICAgdGhpcy5yb290LnJiUmVkID0gZmFsc2U7XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuUkJUcmVlLnByb3RvdHlwZS5yYlJlbW92ZU5vZGUgPSBmdW5jdGlvbihub2RlKSB7XG4gICAgLy8gPj4+IHJoaWxsIDIwMTEtMDUtMjc6IFBlcmZvcm1hbmNlOiBjYWNoZSBwcmV2aW91cy9uZXh0IG5vZGVzXG4gICAgaWYgKG5vZGUucmJOZXh0KSB7XG4gICAgICAgIG5vZGUucmJOZXh0LnJiUHJldmlvdXMgPSBub2RlLnJiUHJldmlvdXM7XG4gICAgICAgIH1cbiAgICBpZiAobm9kZS5yYlByZXZpb3VzKSB7XG4gICAgICAgIG5vZGUucmJQcmV2aW91cy5yYk5leHQgPSBub2RlLnJiTmV4dDtcbiAgICAgICAgfVxuICAgIG5vZGUucmJOZXh0ID0gbm9kZS5yYlByZXZpb3VzID0gbnVsbDtcbiAgICAvLyA8PDxcbiAgICB2YXIgcGFyZW50ID0gbm9kZS5yYlBhcmVudCxcbiAgICAgICAgbGVmdCA9IG5vZGUucmJMZWZ0LFxuICAgICAgICByaWdodCA9IG5vZGUucmJSaWdodCxcbiAgICAgICAgbmV4dDtcbiAgICBpZiAoIWxlZnQpIHtcbiAgICAgICAgbmV4dCA9IHJpZ2h0O1xuICAgICAgICB9XG4gICAgZWxzZSBpZiAoIXJpZ2h0KSB7XG4gICAgICAgIG5leHQgPSBsZWZ0O1xuICAgICAgICB9XG4gICAgZWxzZSB7XG4gICAgICAgIG5leHQgPSB0aGlzLmdldEZpcnN0KHJpZ2h0KTtcbiAgICAgICAgfVxuICAgIGlmIChwYXJlbnQpIHtcbiAgICAgICAgaWYgKHBhcmVudC5yYkxlZnQgPT09IG5vZGUpIHtcbiAgICAgICAgICAgIHBhcmVudC5yYkxlZnQgPSBuZXh0O1xuICAgICAgICAgICAgfVxuICAgICAgICBlbHNlIHtcbiAgICAgICAgICAgIHBhcmVudC5yYlJpZ2h0ID0gbmV4dDtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgIGVsc2Uge1xuICAgICAgICB0aGlzLnJvb3QgPSBuZXh0O1xuICAgICAgICB9XG4gICAgLy8gZW5mb3JjZSByZWQtYmxhY2sgcnVsZXNcbiAgICB2YXIgaXNSZWQ7XG4gICAgaWYgKGxlZnQgJiYgcmlnaHQpIHtcbiAgICAgICAgaXNSZWQgPSBuZXh0LnJiUmVkO1xuICAgICAgICBuZXh0LnJiUmVkID0gbm9kZS5yYlJlZDtcbiAgICAgICAgbmV4dC5yYkxlZnQgPSBsZWZ0O1xuICAgICAgICBsZWZ0LnJiUGFyZW50ID0gbmV4dDtcbiAgICAgICAgaWYgKG5leHQgIT09IHJpZ2h0KSB7XG4gICAgICAgICAgICBwYXJlbnQgPSBuZXh0LnJiUGFyZW50O1xuICAgICAgICAgICAgbmV4dC5yYlBhcmVudCA9IG5vZGUucmJQYXJlbnQ7XG4gICAgICAgICAgICBub2RlID0gbmV4dC5yYlJpZ2h0O1xuICAgICAgICAgICAgcGFyZW50LnJiTGVmdCA9IG5vZGU7XG4gICAgICAgICAgICBuZXh0LnJiUmlnaHQgPSByaWdodDtcbiAgICAgICAgICAgIHJpZ2h0LnJiUGFyZW50ID0gbmV4dDtcbiAgICAgICAgICAgIH1cbiAgICAgICAgZWxzZSB7XG4gICAgICAgICAgICBuZXh0LnJiUGFyZW50ID0gcGFyZW50O1xuICAgICAgICAgICAgcGFyZW50ID0gbmV4dDtcbiAgICAgICAgICAgIG5vZGUgPSBuZXh0LnJiUmlnaHQ7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICBlbHNlIHtcbiAgICAgICAgaXNSZWQgPSBub2RlLnJiUmVkO1xuICAgICAgICBub2RlID0gbmV4dDtcbiAgICAgICAgfVxuICAgIC8vICdub2RlJyBpcyBub3cgdGhlIHNvbGUgc3VjY2Vzc29yJ3MgY2hpbGQgYW5kICdwYXJlbnQnIGl0c1xuICAgIC8vIG5ldyBwYXJlbnQgKHNpbmNlIHRoZSBzdWNjZXNzb3IgY2FuIGhhdmUgYmVlbiBtb3ZlZClcbiAgICBpZiAobm9kZSkge1xuICAgICAgICBub2RlLnJiUGFyZW50ID0gcGFyZW50O1xuICAgICAgICB9XG4gICAgLy8gdGhlICdlYXN5JyBjYXNlc1xuICAgIGlmIChpc1JlZCkge3JldHVybjt9XG4gICAgaWYgKG5vZGUgJiYgbm9kZS5yYlJlZCkge1xuICAgICAgICBub2RlLnJiUmVkID0gZmFsc2U7XG4gICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgIC8vIHRoZSBvdGhlciBjYXNlc1xuICAgIHZhciBzaWJsaW5nO1xuICAgIGRvIHtcbiAgICAgICAgaWYgKG5vZGUgPT09IHRoaXMucm9vdCkge1xuICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICB9XG4gICAgICAgIGlmIChub2RlID09PSBwYXJlbnQucmJMZWZ0KSB7XG4gICAgICAgICAgICBzaWJsaW5nID0gcGFyZW50LnJiUmlnaHQ7XG4gICAgICAgICAgICBpZiAoc2libGluZy5yYlJlZCkge1xuICAgICAgICAgICAgICAgIHNpYmxpbmcucmJSZWQgPSBmYWxzZTtcbiAgICAgICAgICAgICAgICBwYXJlbnQucmJSZWQgPSB0cnVlO1xuICAgICAgICAgICAgICAgIHRoaXMucmJSb3RhdGVMZWZ0KHBhcmVudCk7XG4gICAgICAgICAgICAgICAgc2libGluZyA9IHBhcmVudC5yYlJpZ2h0O1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGlmICgoc2libGluZy5yYkxlZnQgJiYgc2libGluZy5yYkxlZnQucmJSZWQpIHx8IChzaWJsaW5nLnJiUmlnaHQgJiYgc2libGluZy5yYlJpZ2h0LnJiUmVkKSkge1xuICAgICAgICAgICAgICAgIGlmICghc2libGluZy5yYlJpZ2h0IHx8ICFzaWJsaW5nLnJiUmlnaHQucmJSZWQpIHtcbiAgICAgICAgICAgICAgICAgICAgc2libGluZy5yYkxlZnQucmJSZWQgPSBmYWxzZTtcbiAgICAgICAgICAgICAgICAgICAgc2libGluZy5yYlJlZCA9IHRydWU7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMucmJSb3RhdGVSaWdodChzaWJsaW5nKTtcbiAgICAgICAgICAgICAgICAgICAgc2libGluZyA9IHBhcmVudC5yYlJpZ2h0O1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgc2libGluZy5yYlJlZCA9IHBhcmVudC5yYlJlZDtcbiAgICAgICAgICAgICAgICBwYXJlbnQucmJSZWQgPSBzaWJsaW5nLnJiUmlnaHQucmJSZWQgPSBmYWxzZTtcbiAgICAgICAgICAgICAgICB0aGlzLnJiUm90YXRlTGVmdChwYXJlbnQpO1xuICAgICAgICAgICAgICAgIG5vZGUgPSB0aGlzLnJvb3Q7XG4gICAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfVxuICAgICAgICBlbHNlIHtcbiAgICAgICAgICAgIHNpYmxpbmcgPSBwYXJlbnQucmJMZWZ0O1xuICAgICAgICAgICAgaWYgKHNpYmxpbmcucmJSZWQpIHtcbiAgICAgICAgICAgICAgICBzaWJsaW5nLnJiUmVkID0gZmFsc2U7XG4gICAgICAgICAgICAgICAgcGFyZW50LnJiUmVkID0gdHJ1ZTtcbiAgICAgICAgICAgICAgICB0aGlzLnJiUm90YXRlUmlnaHQocGFyZW50KTtcbiAgICAgICAgICAgICAgICBzaWJsaW5nID0gcGFyZW50LnJiTGVmdDtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICBpZiAoKHNpYmxpbmcucmJMZWZ0ICYmIHNpYmxpbmcucmJMZWZ0LnJiUmVkKSB8fCAoc2libGluZy5yYlJpZ2h0ICYmIHNpYmxpbmcucmJSaWdodC5yYlJlZCkpIHtcbiAgICAgICAgICAgICAgICBpZiAoIXNpYmxpbmcucmJMZWZ0IHx8ICFzaWJsaW5nLnJiTGVmdC5yYlJlZCkge1xuICAgICAgICAgICAgICAgICAgICBzaWJsaW5nLnJiUmlnaHQucmJSZWQgPSBmYWxzZTtcbiAgICAgICAgICAgICAgICAgICAgc2libGluZy5yYlJlZCA9IHRydWU7XG4gICAgICAgICAgICAgICAgICAgIHRoaXMucmJSb3RhdGVMZWZ0KHNpYmxpbmcpO1xuICAgICAgICAgICAgICAgICAgICBzaWJsaW5nID0gcGFyZW50LnJiTGVmdDtcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIHNpYmxpbmcucmJSZWQgPSBwYXJlbnQucmJSZWQ7XG4gICAgICAgICAgICAgICAgcGFyZW50LnJiUmVkID0gc2libGluZy5yYkxlZnQucmJSZWQgPSBmYWxzZTtcbiAgICAgICAgICAgICAgICB0aGlzLnJiUm90YXRlUmlnaHQocGFyZW50KTtcbiAgICAgICAgICAgICAgICBub2RlID0gdGhpcy5yb290O1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH1cbiAgICAgICAgc2libGluZy5yYlJlZCA9IHRydWU7XG4gICAgICAgIG5vZGUgPSBwYXJlbnQ7XG4gICAgICAgIHBhcmVudCA9IHBhcmVudC5yYlBhcmVudDtcbiAgICB9IHdoaWxlICghbm9kZS5yYlJlZCk7XG4gICAgaWYgKG5vZGUpIHtub2RlLnJiUmVkID0gZmFsc2U7fVxuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLlJCVHJlZS5wcm90b3R5cGUucmJSb3RhdGVMZWZ0ID0gZnVuY3Rpb24obm9kZSkge1xuICAgIHZhciBwID0gbm9kZSxcbiAgICAgICAgcSA9IG5vZGUucmJSaWdodCwgLy8gY2FuJ3QgYmUgbnVsbFxuICAgICAgICBwYXJlbnQgPSBwLnJiUGFyZW50O1xuICAgIGlmIChwYXJlbnQpIHtcbiAgICAgICAgaWYgKHBhcmVudC5yYkxlZnQgPT09IHApIHtcbiAgICAgICAgICAgIHBhcmVudC5yYkxlZnQgPSBxO1xuICAgICAgICAgICAgfVxuICAgICAgICBlbHNlIHtcbiAgICAgICAgICAgIHBhcmVudC5yYlJpZ2h0ID0gcTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgIGVsc2Uge1xuICAgICAgICB0aGlzLnJvb3QgPSBxO1xuICAgICAgICB9XG4gICAgcS5yYlBhcmVudCA9IHBhcmVudDtcbiAgICBwLnJiUGFyZW50ID0gcTtcbiAgICBwLnJiUmlnaHQgPSBxLnJiTGVmdDtcbiAgICBpZiAocC5yYlJpZ2h0KSB7XG4gICAgICAgIHAucmJSaWdodC5yYlBhcmVudCA9IHA7XG4gICAgICAgIH1cbiAgICBxLnJiTGVmdCA9IHA7XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuUkJUcmVlLnByb3RvdHlwZS5yYlJvdGF0ZVJpZ2h0ID0gZnVuY3Rpb24obm9kZSkge1xuICAgIHZhciBwID0gbm9kZSxcbiAgICAgICAgcSA9IG5vZGUucmJMZWZ0LCAvLyBjYW4ndCBiZSBudWxsXG4gICAgICAgIHBhcmVudCA9IHAucmJQYXJlbnQ7XG4gICAgaWYgKHBhcmVudCkge1xuICAgICAgICBpZiAocGFyZW50LnJiTGVmdCA9PT0gcCkge1xuICAgICAgICAgICAgcGFyZW50LnJiTGVmdCA9IHE7XG4gICAgICAgICAgICB9XG4gICAgICAgIGVsc2Uge1xuICAgICAgICAgICAgcGFyZW50LnJiUmlnaHQgPSBxO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgZWxzZSB7XG4gICAgICAgIHRoaXMucm9vdCA9IHE7XG4gICAgICAgIH1cbiAgICBxLnJiUGFyZW50ID0gcGFyZW50O1xuICAgIHAucmJQYXJlbnQgPSBxO1xuICAgIHAucmJMZWZ0ID0gcS5yYlJpZ2h0O1xuICAgIGlmIChwLnJiTGVmdCkge1xuICAgICAgICBwLnJiTGVmdC5yYlBhcmVudCA9IHA7XG4gICAgICAgIH1cbiAgICBxLnJiUmlnaHQgPSBwO1xuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLlJCVHJlZS5wcm90b3R5cGUuZ2V0Rmlyc3QgPSBmdW5jdGlvbihub2RlKSB7XG4gICAgd2hpbGUgKG5vZGUucmJMZWZ0KSB7XG4gICAgICAgIG5vZGUgPSBub2RlLnJiTGVmdDtcbiAgICAgICAgfVxuICAgIHJldHVybiBub2RlO1xuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLlJCVHJlZS5wcm90b3R5cGUuZ2V0TGFzdCA9IGZ1bmN0aW9uKG5vZGUpIHtcbiAgICB3aGlsZSAobm9kZS5yYlJpZ2h0KSB7XG4gICAgICAgIG5vZGUgPSBub2RlLnJiUmlnaHQ7XG4gICAgICAgIH1cbiAgICByZXR1cm4gbm9kZTtcbiAgICB9O1xuXG4vLyAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS1cbi8vIERpYWdyYW0gbWV0aG9kc1xuXG5Wb3Jvbm9pLnByb3RvdHlwZS5EaWFncmFtID0gZnVuY3Rpb24oc2l0ZSkge1xuICAgIHRoaXMuc2l0ZSA9IHNpdGU7XG4gICAgfTtcblxuLy8gLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tXG4vLyBDZWxsIG1ldGhvZHNcblxuVm9yb25vaS5wcm90b3R5cGUuQ2VsbCA9IGZ1bmN0aW9uKHNpdGUpIHtcbiAgICB0aGlzLnNpdGUgPSBzaXRlO1xuICAgIHRoaXMuaGFsZmVkZ2VzID0gW107XG4gICAgdGhpcy5jbG9zZU1lID0gZmFsc2U7XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuQ2VsbC5wcm90b3R5cGUuaW5pdCA9IGZ1bmN0aW9uKHNpdGUpIHtcbiAgICB0aGlzLnNpdGUgPSBzaXRlO1xuICAgIHRoaXMuaGFsZmVkZ2VzID0gW107XG4gICAgdGhpcy5jbG9zZU1lID0gZmFsc2U7XG4gICAgcmV0dXJuIHRoaXM7XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuY3JlYXRlQ2VsbCA9IGZ1bmN0aW9uKHNpdGUpIHtcbiAgICB2YXIgY2VsbCA9IHRoaXMuY2VsbEp1bmt5YXJkLnBvcCgpO1xuICAgIGlmICggY2VsbCApIHtcbiAgICAgICAgcmV0dXJuIGNlbGwuaW5pdChzaXRlKTtcbiAgICAgICAgfVxuICAgIHJldHVybiBuZXcgdGhpcy5DZWxsKHNpdGUpO1xuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLkNlbGwucHJvdG90eXBlLnByZXBhcmVIYWxmZWRnZXMgPSBmdW5jdGlvbigpIHtcbiAgICB2YXIgaGFsZmVkZ2VzID0gdGhpcy5oYWxmZWRnZXMsXG4gICAgICAgIGlIYWxmZWRnZSA9IGhhbGZlZGdlcy5sZW5ndGgsXG4gICAgICAgIGVkZ2U7XG4gICAgLy8gZ2V0IHJpZCBvZiB1bnVzZWQgaGFsZmVkZ2VzXG4gICAgLy8gcmhpbGwgMjAxMS0wNS0yNzogS2VlcCBpdCBzaW1wbGUsIG5vIHBvaW50IGhlcmUgaW4gdHJ5aW5nXG4gICAgLy8gdG8gYmUgZmFuY3k6IGRhbmdsaW5nIGVkZ2VzIGFyZSBhIHR5cGljYWxseSBhIG1pbm9yaXR5LlxuICAgIHdoaWxlIChpSGFsZmVkZ2UtLSkge1xuICAgICAgICBlZGdlID0gaGFsZmVkZ2VzW2lIYWxmZWRnZV0uZWRnZTtcbiAgICAgICAgaWYgKCFlZGdlLnZiIHx8ICFlZGdlLnZhKSB7XG4gICAgICAgICAgICBoYWxmZWRnZXMuc3BsaWNlKGlIYWxmZWRnZSwxKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuXG4gICAgLy8gcmhpbGwgMjAxMS0wNS0yNjogSSB0cmllZCB0byB1c2UgYSBiaW5hcnkgc2VhcmNoIGF0IGluc2VydGlvblxuICAgIC8vIHRpbWUgdG8ga2VlcCB0aGUgYXJyYXkgc29ydGVkIG9uLXRoZS1mbHkgKGluIENlbGwuYWRkSGFsZmVkZ2UoKSkuXG4gICAgLy8gVGhlcmUgd2FzIG5vIHJlYWwgYmVuZWZpdHMgaW4gZG9pbmcgc28sIHBlcmZvcm1hbmNlIG9uXG4gICAgLy8gRmlyZWZveCAzLjYgd2FzIGltcHJvdmVkIG1hcmdpbmFsbHksIHdoaWxlIHBlcmZvcm1hbmNlIG9uXG4gICAgLy8gT3BlcmEgMTEgd2FzIHBlbmFsaXplZCBtYXJnaW5hbGx5LlxuICAgIGhhbGZlZGdlcy5zb3J0KGZ1bmN0aW9uKGEsYil7cmV0dXJuIGIuYW5nbGUtYS5hbmdsZTt9KTtcbiAgICByZXR1cm4gaGFsZmVkZ2VzLmxlbmd0aDtcbiAgICB9O1xuXG4vLyBSZXR1cm4gYSBsaXN0IG9mIHRoZSBuZWlnaGJvciBJZHNcblZvcm9ub2kucHJvdG90eXBlLkNlbGwucHJvdG90eXBlLmdldE5laWdoYm9ySWRzID0gZnVuY3Rpb24oKSB7XG4gICAgdmFyIG5laWdoYm9ycyA9IFtdLFxuICAgICAgICBpSGFsZmVkZ2UgPSB0aGlzLmhhbGZlZGdlcy5sZW5ndGgsXG4gICAgICAgIGVkZ2U7XG4gICAgd2hpbGUgKGlIYWxmZWRnZS0tKXtcbiAgICAgICAgZWRnZSA9IHRoaXMuaGFsZmVkZ2VzW2lIYWxmZWRnZV0uZWRnZTtcbiAgICAgICAgaWYgKGVkZ2UubFNpdGUgIT09IG51bGwgJiYgZWRnZS5sU2l0ZS52b3Jvbm9pSWQgIT0gdGhpcy5zaXRlLnZvcm9ub2lJZCkge1xuICAgICAgICAgICAgbmVpZ2hib3JzLnB1c2goZWRnZS5sU2l0ZS52b3Jvbm9pSWQpO1xuICAgICAgICAgICAgfVxuICAgICAgICBlbHNlIGlmIChlZGdlLnJTaXRlICE9PSBudWxsICYmIGVkZ2UuclNpdGUudm9yb25vaUlkICE9IHRoaXMuc2l0ZS52b3Jvbm9pSWQpe1xuICAgICAgICAgICAgbmVpZ2hib3JzLnB1c2goZWRnZS5yU2l0ZS52b3Jvbm9pSWQpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgcmV0dXJuIG5laWdoYm9ycztcbiAgICB9O1xuXG4vLyBDb21wdXRlIGJvdW5kaW5nIGJveFxuLy9cblZvcm9ub2kucHJvdG90eXBlLkNlbGwucHJvdG90eXBlLmdldEJib3ggPSBmdW5jdGlvbigpIHtcbiAgICB2YXIgaGFsZmVkZ2VzID0gdGhpcy5oYWxmZWRnZXMsXG4gICAgICAgIGlIYWxmZWRnZSA9IGhhbGZlZGdlcy5sZW5ndGgsXG4gICAgICAgIHhtaW4gPSBJbmZpbml0eSxcbiAgICAgICAgeW1pbiA9IEluZmluaXR5LFxuICAgICAgICB4bWF4ID0gLUluZmluaXR5LFxuICAgICAgICB5bWF4ID0gLUluZmluaXR5LFxuICAgICAgICB2LCB2eCwgdnk7XG4gICAgd2hpbGUgKGlIYWxmZWRnZS0tKSB7XG4gICAgICAgIHYgPSBoYWxmZWRnZXNbaUhhbGZlZGdlXS5nZXRTdGFydHBvaW50KCk7XG4gICAgICAgIHZ4ID0gdi54O1xuICAgICAgICB2eSA9IHYueTtcbiAgICAgICAgaWYgKHZ4IDwgeG1pbikge3htaW4gPSB2eDt9XG4gICAgICAgIGlmICh2eSA8IHltaW4pIHt5bWluID0gdnk7fVxuICAgICAgICBpZiAodnggPiB4bWF4KSB7eG1heCA9IHZ4O31cbiAgICAgICAgaWYgKHZ5ID4geW1heCkge3ltYXggPSB2eTt9XG4gICAgICAgIC8vIHdlIGRvbnQgbmVlZCB0byB0YWtlIGludG8gYWNjb3VudCBlbmQgcG9pbnQsXG4gICAgICAgIC8vIHNpbmNlIGVhY2ggZW5kIHBvaW50IG1hdGNoZXMgYSBzdGFydCBwb2ludFxuICAgICAgICB9XG4gICAgcmV0dXJuIHtcbiAgICAgICAgeDogeG1pbixcbiAgICAgICAgeTogeW1pbixcbiAgICAgICAgd2lkdGg6IHhtYXgteG1pbixcbiAgICAgICAgaGVpZ2h0OiB5bWF4LXltaW5cbiAgICAgICAgfTtcbiAgICB9O1xuXG4vLyBSZXR1cm4gd2hldGhlciBhIHBvaW50IGlzIGluc2lkZSwgb24sIG9yIG91dHNpZGUgdGhlIGNlbGw6XG4vLyAgIC0xOiBwb2ludCBpcyBvdXRzaWRlIHRoZSBwZXJpbWV0ZXIgb2YgdGhlIGNlbGxcbi8vICAgIDA6IHBvaW50IGlzIG9uIHRoZSBwZXJpbWV0ZXIgb2YgdGhlIGNlbGxcbi8vICAgIDE6IHBvaW50IGlzIGluc2lkZSB0aGUgcGVyaW1ldGVyIG9mIHRoZSBjZWxsXG4vL1xuVm9yb25vaS5wcm90b3R5cGUuQ2VsbC5wcm90b3R5cGUucG9pbnRJbnRlcnNlY3Rpb24gPSBmdW5jdGlvbih4LCB5KSB7XG4gICAgLy8gQ2hlY2sgaWYgcG9pbnQgaW4gcG9seWdvbi4gU2luY2UgYWxsIHBvbHlnb25zIG9mIGEgVm9yb25vaVxuICAgIC8vIGRpYWdyYW0gYXJlIGNvbnZleCwgdGhlbjpcbiAgICAvLyBodHRwOi8vcGF1bGJvdXJrZS5uZXQvZ2VvbWV0cnkvcG9seWdvbm1lc2gvXG4gICAgLy8gU29sdXRpb24gMyAoMkQpOlxuICAgIC8vICAgXCJJZiB0aGUgcG9seWdvbiBpcyBjb252ZXggdGhlbiBvbmUgY2FuIGNvbnNpZGVyIHRoZSBwb2x5Z29uXG4gICAgLy8gICBcImFzIGEgJ3BhdGgnIGZyb20gdGhlIGZpcnN0IHZlcnRleC4gQSBwb2ludCBpcyBvbiB0aGUgaW50ZXJpb3JcbiAgICAvLyAgIFwib2YgdGhpcyBwb2x5Z29ucyBpZiBpdCBpcyBhbHdheXMgb24gdGhlIHNhbWUgc2lkZSBvZiBhbGwgdGhlXG4gICAgLy8gICBcImxpbmUgc2VnbWVudHMgbWFraW5nIHVwIHRoZSBwYXRoLiAuLi5cbiAgICAvLyAgIFwiKHkgLSB5MCkgKHgxIC0geDApIC0gKHggLSB4MCkgKHkxIC0geTApXG4gICAgLy8gICBcImlmIGl0IGlzIGxlc3MgdGhhbiAwIHRoZW4gUCBpcyB0byB0aGUgcmlnaHQgb2YgdGhlIGxpbmUgc2VnbWVudCxcbiAgICAvLyAgIFwiaWYgZ3JlYXRlciB0aGFuIDAgaXQgaXMgdG8gdGhlIGxlZnQsIGlmIGVxdWFsIHRvIDAgdGhlbiBpdCBsaWVzXG4gICAgLy8gICBcIm9uIHRoZSBsaW5lIHNlZ21lbnRcIlxuICAgIHZhciBoYWxmZWRnZXMgPSB0aGlzLmhhbGZlZGdlcyxcbiAgICAgICAgaUhhbGZlZGdlID0gaGFsZmVkZ2VzLmxlbmd0aCxcbiAgICAgICAgaGFsZmVkZ2UsXG4gICAgICAgIHAwLCBwMSwgcjtcbiAgICB3aGlsZSAoaUhhbGZlZGdlLS0pIHtcbiAgICAgICAgaGFsZmVkZ2UgPSBoYWxmZWRnZXNbaUhhbGZlZGdlXTtcbiAgICAgICAgcDAgPSBoYWxmZWRnZS5nZXRTdGFydHBvaW50KCk7XG4gICAgICAgIHAxID0gaGFsZmVkZ2UuZ2V0RW5kcG9pbnQoKTtcbiAgICAgICAgciA9ICh5LXAwLnkpKihwMS54LXAwLngpLSh4LXAwLngpKihwMS55LXAwLnkpO1xuICAgICAgICBpZiAoIXIpIHtcbiAgICAgICAgICAgIHJldHVybiAwO1xuICAgICAgICAgICAgfVxuICAgICAgICBpZiAociA+IDApIHtcbiAgICAgICAgICAgIHJldHVybiAtMTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgIHJldHVybiAxO1xuICAgIH07XG5cbi8vIC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLVxuLy8gRWRnZSBtZXRob2RzXG4vL1xuXG5Wb3Jvbm9pLnByb3RvdHlwZS5WZXJ0ZXggPSBmdW5jdGlvbih4LCB5KSB7XG4gICAgdGhpcy54ID0geDtcbiAgICB0aGlzLnkgPSB5O1xuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLkVkZ2UgPSBmdW5jdGlvbihsU2l0ZSwgclNpdGUpIHtcbiAgICB0aGlzLmxTaXRlID0gbFNpdGU7XG4gICAgdGhpcy5yU2l0ZSA9IHJTaXRlO1xuICAgIHRoaXMudmEgPSB0aGlzLnZiID0gbnVsbDtcbiAgICB9O1xuXG5Wb3Jvbm9pLnByb3RvdHlwZS5IYWxmZWRnZSA9IGZ1bmN0aW9uKGVkZ2UsIGxTaXRlLCByU2l0ZSkge1xuICAgIHRoaXMuc2l0ZSA9IGxTaXRlO1xuICAgIHRoaXMuZWRnZSA9IGVkZ2U7XG4gICAgLy8gJ2FuZ2xlJyBpcyBhIHZhbHVlIHRvIGJlIHVzZWQgZm9yIHByb3Blcmx5IHNvcnRpbmcgdGhlXG4gICAgLy8gaGFsZnNlZ21lbnRzIGNvdW50ZXJjbG9ja3dpc2UuIEJ5IGNvbnZlbnRpb24sIHdlIHdpbGxcbiAgICAvLyB1c2UgdGhlIGFuZ2xlIG9mIHRoZSBsaW5lIGRlZmluZWQgYnkgdGhlICdzaXRlIHRvIHRoZSBsZWZ0J1xuICAgIC8vIHRvIHRoZSAnc2l0ZSB0byB0aGUgcmlnaHQnLlxuICAgIC8vIEhvd2V2ZXIsIGJvcmRlciBlZGdlcyBoYXZlIG5vICdzaXRlIHRvIHRoZSByaWdodCc6IHRodXMgd2VcbiAgICAvLyB1c2UgdGhlIGFuZ2xlIG9mIGxpbmUgcGVycGVuZGljdWxhciB0byB0aGUgaGFsZnNlZ21lbnQgKHRoZVxuICAgIC8vIGVkZ2Ugc2hvdWxkIGhhdmUgYm90aCBlbmQgcG9pbnRzIGRlZmluZWQgaW4gc3VjaCBjYXNlLilcbiAgICBpZiAoclNpdGUpIHtcbiAgICAgICAgdGhpcy5hbmdsZSA9IE1hdGguYXRhbjIoclNpdGUueS1sU2l0ZS55LCByU2l0ZS54LWxTaXRlLngpO1xuICAgICAgICB9XG4gICAgZWxzZSB7XG4gICAgICAgIHZhciB2YSA9IGVkZ2UudmEsXG4gICAgICAgICAgICB2YiA9IGVkZ2UudmI7XG4gICAgICAgIC8vIHJoaWxsIDIwMTEtMDUtMzE6IHVzZWQgdG8gY2FsbCBnZXRTdGFydHBvaW50KCkvZ2V0RW5kcG9pbnQoKSxcbiAgICAgICAgLy8gYnV0IGZvciBwZXJmb3JtYW5jZSBwdXJwb3NlLCB0aGVzZSBhcmUgZXhwYW5kZWQgaW4gcGxhY2UgaGVyZS5cbiAgICAgICAgdGhpcy5hbmdsZSA9IGVkZ2UubFNpdGUgPT09IGxTaXRlID9cbiAgICAgICAgICAgIE1hdGguYXRhbjIodmIueC12YS54LCB2YS55LXZiLnkpIDpcbiAgICAgICAgICAgIE1hdGguYXRhbjIodmEueC12Yi54LCB2Yi55LXZhLnkpO1xuICAgICAgICB9XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuY3JlYXRlSGFsZmVkZ2UgPSBmdW5jdGlvbihlZGdlLCBsU2l0ZSwgclNpdGUpIHtcbiAgICByZXR1cm4gbmV3IHRoaXMuSGFsZmVkZ2UoZWRnZSwgbFNpdGUsIHJTaXRlKTtcbiAgICB9O1xuXG5Wb3Jvbm9pLnByb3RvdHlwZS5IYWxmZWRnZS5wcm90b3R5cGUuZ2V0U3RhcnRwb2ludCA9IGZ1bmN0aW9uKCkge1xuICAgIHJldHVybiB0aGlzLmVkZ2UubFNpdGUgPT09IHRoaXMuc2l0ZSA/IHRoaXMuZWRnZS52YSA6IHRoaXMuZWRnZS52YjtcbiAgICB9O1xuXG5Wb3Jvbm9pLnByb3RvdHlwZS5IYWxmZWRnZS5wcm90b3R5cGUuZ2V0RW5kcG9pbnQgPSBmdW5jdGlvbigpIHtcbiAgICByZXR1cm4gdGhpcy5lZGdlLmxTaXRlID09PSB0aGlzLnNpdGUgPyB0aGlzLmVkZ2UudmIgOiB0aGlzLmVkZ2UudmE7XG4gICAgfTtcblxuXG5cbi8vIHRoaXMgY3JlYXRlIGFuZCBhZGQgYSB2ZXJ0ZXggdG8gdGhlIGludGVybmFsIGNvbGxlY3Rpb25cblxuVm9yb25vaS5wcm90b3R5cGUuY3JlYXRlVmVydGV4ID0gZnVuY3Rpb24oeCwgeSkge1xuICAgIHZhciB2ID0gdGhpcy52ZXJ0ZXhKdW5reWFyZC5wb3AoKTtcbiAgICBpZiAoICF2ICkge1xuICAgICAgICB2ID0gbmV3IHRoaXMuVmVydGV4KHgsIHkpO1xuICAgICAgICB9XG4gICAgZWxzZSB7XG4gICAgICAgIHYueCA9IHg7XG4gICAgICAgIHYueSA9IHk7XG4gICAgICAgIH1cbiAgICB0aGlzLnZlcnRpY2VzLnB1c2godik7XG4gICAgcmV0dXJuIHY7XG4gICAgfTtcblxuLy8gdGhpcyBjcmVhdGUgYW5kIGFkZCBhbiBlZGdlIHRvIGludGVybmFsIGNvbGxlY3Rpb24sIGFuZCBhbHNvIGNyZWF0ZVxuLy8gdHdvIGhhbGZlZGdlcyB3aGljaCBhcmUgYWRkZWQgdG8gZWFjaCBzaXRlJ3MgY291bnRlcmNsb2Nrd2lzZSBhcnJheVxuLy8gb2YgaGFsZmVkZ2VzLlxuXG5Wb3Jvbm9pLnByb3RvdHlwZS5jcmVhdGVFZGdlID0gZnVuY3Rpb24obFNpdGUsIHJTaXRlLCB2YSwgdmIpIHtcbiAgICB2YXIgZWRnZSA9IHRoaXMuZWRnZUp1bmt5YXJkLnBvcCgpO1xuICAgIGlmICggIWVkZ2UgKSB7XG4gICAgICAgIGVkZ2UgPSBuZXcgdGhpcy5FZGdlKGxTaXRlLCByU2l0ZSk7XG4gICAgICAgIH1cbiAgICBlbHNlIHtcbiAgICAgICAgZWRnZS5sU2l0ZSA9IGxTaXRlO1xuICAgICAgICBlZGdlLnJTaXRlID0gclNpdGU7XG4gICAgICAgIGVkZ2UudmEgPSBlZGdlLnZiID0gbnVsbDtcbiAgICAgICAgfVxuXG4gICAgdGhpcy5lZGdlcy5wdXNoKGVkZ2UpO1xuICAgIGlmICh2YSkge1xuICAgICAgICB0aGlzLnNldEVkZ2VTdGFydHBvaW50KGVkZ2UsIGxTaXRlLCByU2l0ZSwgdmEpO1xuICAgICAgICB9XG4gICAgaWYgKHZiKSB7XG4gICAgICAgIHRoaXMuc2V0RWRnZUVuZHBvaW50KGVkZ2UsIGxTaXRlLCByU2l0ZSwgdmIpO1xuICAgICAgICB9XG4gICAgdGhpcy5jZWxsc1tsU2l0ZS52b3Jvbm9pSWRdLmhhbGZlZGdlcy5wdXNoKHRoaXMuY3JlYXRlSGFsZmVkZ2UoZWRnZSwgbFNpdGUsIHJTaXRlKSk7XG4gICAgdGhpcy5jZWxsc1tyU2l0ZS52b3Jvbm9pSWRdLmhhbGZlZGdlcy5wdXNoKHRoaXMuY3JlYXRlSGFsZmVkZ2UoZWRnZSwgclNpdGUsIGxTaXRlKSk7XG4gICAgcmV0dXJuIGVkZ2U7XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuY3JlYXRlQm9yZGVyRWRnZSA9IGZ1bmN0aW9uKGxTaXRlLCB2YSwgdmIpIHtcbiAgICB2YXIgZWRnZSA9IHRoaXMuZWRnZUp1bmt5YXJkLnBvcCgpO1xuICAgIGlmICggIWVkZ2UgKSB7XG4gICAgICAgIGVkZ2UgPSBuZXcgdGhpcy5FZGdlKGxTaXRlLCBudWxsKTtcbiAgICAgICAgfVxuICAgIGVsc2Uge1xuICAgICAgICBlZGdlLmxTaXRlID0gbFNpdGU7XG4gICAgICAgIGVkZ2UuclNpdGUgPSBudWxsO1xuICAgICAgICB9XG4gICAgZWRnZS52YSA9IHZhO1xuICAgIGVkZ2UudmIgPSB2YjtcbiAgICB0aGlzLmVkZ2VzLnB1c2goZWRnZSk7XG4gICAgcmV0dXJuIGVkZ2U7XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuc2V0RWRnZVN0YXJ0cG9pbnQgPSBmdW5jdGlvbihlZGdlLCBsU2l0ZSwgclNpdGUsIHZlcnRleCkge1xuICAgIGlmICghZWRnZS52YSAmJiAhZWRnZS52Yikge1xuICAgICAgICBlZGdlLnZhID0gdmVydGV4O1xuICAgICAgICBlZGdlLmxTaXRlID0gbFNpdGU7XG4gICAgICAgIGVkZ2UuclNpdGUgPSByU2l0ZTtcbiAgICAgICAgfVxuICAgIGVsc2UgaWYgKGVkZ2UubFNpdGUgPT09IHJTaXRlKSB7XG4gICAgICAgIGVkZ2UudmIgPSB2ZXJ0ZXg7XG4gICAgICAgIH1cbiAgICBlbHNlIHtcbiAgICAgICAgZWRnZS52YSA9IHZlcnRleDtcbiAgICAgICAgfVxuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLnNldEVkZ2VFbmRwb2ludCA9IGZ1bmN0aW9uKGVkZ2UsIGxTaXRlLCByU2l0ZSwgdmVydGV4KSB7XG4gICAgdGhpcy5zZXRFZGdlU3RhcnRwb2ludChlZGdlLCByU2l0ZSwgbFNpdGUsIHZlcnRleCk7XG4gICAgfTtcblxuLy8gLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tXG4vLyBCZWFjaGxpbmUgbWV0aG9kc1xuXG4vLyByaGlsbCAyMDExLTA2LTA3OiBGb3Igc29tZSByZWFzb25zLCBwZXJmb3JtYW5jZSBzdWZmZXJzIHNpZ25pZmljYW50bHlcbi8vIHdoZW4gaW5zdGFuY2lhdGluZyBhIGxpdGVyYWwgb2JqZWN0IGluc3RlYWQgb2YgYW4gZW1wdHkgY3RvclxuVm9yb25vaS5wcm90b3R5cGUuQmVhY2hzZWN0aW9uID0gZnVuY3Rpb24oKSB7XG4gICAgfTtcblxuLy8gcmhpbGwgMjAxMS0wNi0wMjogQSBsb3Qgb2YgQmVhY2hzZWN0aW9uIGluc3RhbmNpYXRpb25zXG4vLyBvY2N1ciBkdXJpbmcgdGhlIGNvbXB1dGF0aW9uIG9mIHRoZSBWb3Jvbm9pIGRpYWdyYW0sXG4vLyBzb21ld2hlcmUgYmV0d2VlbiB0aGUgbnVtYmVyIG9mIHNpdGVzIGFuZCB0d2ljZSB0aGVcbi8vIG51bWJlciBvZiBzaXRlcywgd2hpbGUgdGhlIG51bWJlciBvZiBCZWFjaHNlY3Rpb25zIG9uIHRoZVxuLy8gYmVhY2hsaW5lIGF0IGFueSBnaXZlbiB0aW1lIGlzIGNvbXBhcmF0aXZlbHkgbG93LiBGb3IgdGhpc1xuLy8gcmVhc29uLCB3ZSByZXVzZSBhbHJlYWR5IGNyZWF0ZWQgQmVhY2hzZWN0aW9ucywgaW4gb3JkZXJcbi8vIHRvIGF2b2lkIG5ldyBtZW1vcnkgYWxsb2NhdGlvbi4gVGhpcyByZXN1bHRlZCBpbiBhIG1lYXN1cmFibGVcbi8vIHBlcmZvcm1hbmNlIGdhaW4uXG5cblZvcm9ub2kucHJvdG90eXBlLmNyZWF0ZUJlYWNoc2VjdGlvbiA9IGZ1bmN0aW9uKHNpdGUpIHtcbiAgICB2YXIgYmVhY2hzZWN0aW9uID0gdGhpcy5iZWFjaHNlY3Rpb25KdW5reWFyZC5wb3AoKTtcbiAgICBpZiAoIWJlYWNoc2VjdGlvbikge1xuICAgICAgICBiZWFjaHNlY3Rpb24gPSBuZXcgdGhpcy5CZWFjaHNlY3Rpb24oKTtcbiAgICAgICAgfVxuICAgIGJlYWNoc2VjdGlvbi5zaXRlID0gc2l0ZTtcbiAgICByZXR1cm4gYmVhY2hzZWN0aW9uO1xuICAgIH07XG5cbi8vIGNhbGN1bGF0ZSB0aGUgbGVmdCBicmVhayBwb2ludCBvZiBhIHBhcnRpY3VsYXIgYmVhY2ggc2VjdGlvbixcbi8vIGdpdmVuIGEgcGFydGljdWxhciBzd2VlcCBsaW5lXG5Wb3Jvbm9pLnByb3RvdHlwZS5sZWZ0QnJlYWtQb2ludCA9IGZ1bmN0aW9uKGFyYywgZGlyZWN0cml4KSB7XG4gICAgLy8gaHR0cDovL2VuLndpa2lwZWRpYS5vcmcvd2lraS9QYXJhYm9sYVxuICAgIC8vIGh0dHA6Ly9lbi53aWtpcGVkaWEub3JnL3dpa2kvUXVhZHJhdGljX2VxdWF0aW9uXG4gICAgLy8gaDEgPSB4MSxcbiAgICAvLyBrMSA9ICh5MStkaXJlY3RyaXgpLzIsXG4gICAgLy8gaDIgPSB4MixcbiAgICAvLyBrMiA9ICh5MitkaXJlY3RyaXgpLzIsXG4gICAgLy8gcDEgPSBrMS1kaXJlY3RyaXgsXG4gICAgLy8gYTEgPSAxLyg0KnAxKSxcbiAgICAvLyBiMSA9IC1oMS8oMipwMSksXG4gICAgLy8gYzEgPSBoMSpoMS8oNCpwMSkrazEsXG4gICAgLy8gcDIgPSBrMi1kaXJlY3RyaXgsXG4gICAgLy8gYTIgPSAxLyg0KnAyKSxcbiAgICAvLyBiMiA9IC1oMi8oMipwMiksXG4gICAgLy8gYzIgPSBoMipoMi8oNCpwMikrazIsXG4gICAgLy8geCA9ICgtKGIyLWIxKSArIE1hdGguc3FydCgoYjItYjEpKihiMi1iMSkgLSA0KihhMi1hMSkqKGMyLWMxKSkpIC8gKDIqKGEyLWExKSlcbiAgICAvLyBXaGVuIHgxIGJlY29tZSB0aGUgeC1vcmlnaW46XG4gICAgLy8gaDEgPSAwLFxuICAgIC8vIGsxID0gKHkxK2RpcmVjdHJpeCkvMixcbiAgICAvLyBoMiA9IHgyLXgxLFxuICAgIC8vIGsyID0gKHkyK2RpcmVjdHJpeCkvMixcbiAgICAvLyBwMSA9IGsxLWRpcmVjdHJpeCxcbiAgICAvLyBhMSA9IDEvKDQqcDEpLFxuICAgIC8vIGIxID0gMCxcbiAgICAvLyBjMSA9IGsxLFxuICAgIC8vIHAyID0gazItZGlyZWN0cml4LFxuICAgIC8vIGEyID0gMS8oNCpwMiksXG4gICAgLy8gYjIgPSAtaDIvKDIqcDIpLFxuICAgIC8vIGMyID0gaDIqaDIvKDQqcDIpK2syLFxuICAgIC8vIHggPSAoLWIyICsgTWF0aC5zcXJ0KGIyKmIyIC0gNCooYTItYTEpKihjMi1rMSkpKSAvICgyKihhMi1hMSkpICsgeDFcblxuICAgIC8vIGNoYW5nZSBjb2RlIGJlbG93IGF0IHlvdXIgb3duIHJpc2s6IGNhcmUgaGFzIGJlZW4gdGFrZW4gdG9cbiAgICAvLyByZWR1Y2UgZXJyb3JzIGR1ZSB0byBjb21wdXRlcnMnIGZpbml0ZSBhcml0aG1ldGljIHByZWNpc2lvbi5cbiAgICAvLyBNYXliZSBjYW4gc3RpbGwgYmUgaW1wcm92ZWQsIHdpbGwgc2VlIGlmIGFueSBtb3JlIG9mIHRoaXNcbiAgICAvLyBraW5kIG9mIGVycm9ycyBwb3AgdXAgYWdhaW4uXG4gICAgdmFyIHNpdGUgPSBhcmMuc2l0ZSxcbiAgICAgICAgcmZvY3ggPSBzaXRlLngsXG4gICAgICAgIHJmb2N5ID0gc2l0ZS55LFxuICAgICAgICBwYnkyID0gcmZvY3ktZGlyZWN0cml4O1xuICAgIC8vIHBhcmFib2xhIGluIGRlZ2VuZXJhdGUgY2FzZSB3aGVyZSBmb2N1cyBpcyBvbiBkaXJlY3RyaXhcbiAgICBpZiAoIXBieTIpIHtcbiAgICAgICAgcmV0dXJuIHJmb2N4O1xuICAgICAgICB9XG4gICAgdmFyIGxBcmMgPSBhcmMucmJQcmV2aW91cztcbiAgICBpZiAoIWxBcmMpIHtcbiAgICAgICAgcmV0dXJuIC1JbmZpbml0eTtcbiAgICAgICAgfVxuICAgIHNpdGUgPSBsQXJjLnNpdGU7XG4gICAgdmFyIGxmb2N4ID0gc2l0ZS54LFxuICAgICAgICBsZm9jeSA9IHNpdGUueSxcbiAgICAgICAgcGxieTIgPSBsZm9jeS1kaXJlY3RyaXg7XG4gICAgLy8gcGFyYWJvbGEgaW4gZGVnZW5lcmF0ZSBjYXNlIHdoZXJlIGZvY3VzIGlzIG9uIGRpcmVjdHJpeFxuICAgIGlmICghcGxieTIpIHtcbiAgICAgICAgcmV0dXJuIGxmb2N4O1xuICAgICAgICB9XG4gICAgdmFyIGhsID0gbGZvY3gtcmZvY3gsXG4gICAgICAgIGFieTIgPSAxL3BieTItMS9wbGJ5MixcbiAgICAgICAgYiA9IGhsL3BsYnkyO1xuICAgIGlmIChhYnkyKSB7XG4gICAgICAgIHJldHVybiAoLWIrdGhpcy5zcXJ0KGIqYi0yKmFieTIqKGhsKmhsLygtMipwbGJ5MiktbGZvY3krcGxieTIvMityZm9jeS1wYnkyLzIpKSkvYWJ5MityZm9jeDtcbiAgICAgICAgfVxuICAgIC8vIGJvdGggcGFyYWJvbGFzIGhhdmUgc2FtZSBkaXN0YW5jZSB0byBkaXJlY3RyaXgsIHRodXMgYnJlYWsgcG9pbnQgaXMgbWlkd2F5XG4gICAgcmV0dXJuIChyZm9jeCtsZm9jeCkvMjtcbiAgICB9O1xuXG4vLyBjYWxjdWxhdGUgdGhlIHJpZ2h0IGJyZWFrIHBvaW50IG9mIGEgcGFydGljdWxhciBiZWFjaCBzZWN0aW9uLFxuLy8gZ2l2ZW4gYSBwYXJ0aWN1bGFyIGRpcmVjdHJpeFxuVm9yb25vaS5wcm90b3R5cGUucmlnaHRCcmVha1BvaW50ID0gZnVuY3Rpb24oYXJjLCBkaXJlY3RyaXgpIHtcbiAgICB2YXIgckFyYyA9IGFyYy5yYk5leHQ7XG4gICAgaWYgKHJBcmMpIHtcbiAgICAgICAgcmV0dXJuIHRoaXMubGVmdEJyZWFrUG9pbnQockFyYywgZGlyZWN0cml4KTtcbiAgICAgICAgfVxuICAgIHZhciBzaXRlID0gYXJjLnNpdGU7XG4gICAgcmV0dXJuIHNpdGUueSA9PT0gZGlyZWN0cml4ID8gc2l0ZS54IDogSW5maW5pdHk7XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuZGV0YWNoQmVhY2hzZWN0aW9uID0gZnVuY3Rpb24oYmVhY2hzZWN0aW9uKSB7XG4gICAgdGhpcy5kZXRhY2hDaXJjbGVFdmVudChiZWFjaHNlY3Rpb24pOyAvLyBkZXRhY2ggcG90ZW50aWFsbHkgYXR0YWNoZWQgY2lyY2xlIGV2ZW50XG4gICAgdGhpcy5iZWFjaGxpbmUucmJSZW1vdmVOb2RlKGJlYWNoc2VjdGlvbik7IC8vIHJlbW92ZSBmcm9tIFJCLXRyZWVcbiAgICB0aGlzLmJlYWNoc2VjdGlvbkp1bmt5YXJkLnB1c2goYmVhY2hzZWN0aW9uKTsgLy8gbWFyayBmb3IgcmV1c2VcbiAgICB9O1xuXG5Wb3Jvbm9pLnByb3RvdHlwZS5yZW1vdmVCZWFjaHNlY3Rpb24gPSBmdW5jdGlvbihiZWFjaHNlY3Rpb24pIHtcbiAgICB2YXIgY2lyY2xlID0gYmVhY2hzZWN0aW9uLmNpcmNsZUV2ZW50LFxuICAgICAgICB4ID0gY2lyY2xlLngsXG4gICAgICAgIHkgPSBjaXJjbGUueWNlbnRlcixcbiAgICAgICAgdmVydGV4ID0gdGhpcy5jcmVhdGVWZXJ0ZXgoeCwgeSksXG4gICAgICAgIHByZXZpb3VzID0gYmVhY2hzZWN0aW9uLnJiUHJldmlvdXMsXG4gICAgICAgIG5leHQgPSBiZWFjaHNlY3Rpb24ucmJOZXh0LFxuICAgICAgICBkaXNhcHBlYXJpbmdUcmFuc2l0aW9ucyA9IFtiZWFjaHNlY3Rpb25dLFxuICAgICAgICBhYnNfZm4gPSBNYXRoLmFicztcblxuICAgIC8vIHJlbW92ZSBjb2xsYXBzZWQgYmVhY2hzZWN0aW9uIGZyb20gYmVhY2hsaW5lXG4gICAgdGhpcy5kZXRhY2hCZWFjaHNlY3Rpb24oYmVhY2hzZWN0aW9uKTtcblxuICAgIC8vIHRoZXJlIGNvdWxkIGJlIG1vcmUgdGhhbiBvbmUgZW1wdHkgYXJjIGF0IHRoZSBkZWxldGlvbiBwb2ludCwgdGhpc1xuICAgIC8vIGhhcHBlbnMgd2hlbiBtb3JlIHRoYW4gdHdvIGVkZ2VzIGFyZSBsaW5rZWQgYnkgdGhlIHNhbWUgdmVydGV4LFxuICAgIC8vIHNvIHdlIHdpbGwgY29sbGVjdCBhbGwgdGhvc2UgZWRnZXMgYnkgbG9va2luZyB1cCBib3RoIHNpZGVzIG9mXG4gICAgLy8gdGhlIGRlbGV0aW9uIHBvaW50LlxuICAgIC8vIGJ5IHRoZSB3YXksIHRoZXJlIGlzICphbHdheXMqIGEgcHJlZGVjZXNzb3Ivc3VjY2Vzc29yIHRvIGFueSBjb2xsYXBzZWRcbiAgICAvLyBiZWFjaCBzZWN0aW9uLCBpdCdzIGp1c3QgaW1wb3NzaWJsZSB0byBoYXZlIGEgY29sbGFwc2luZyBmaXJzdC9sYXN0XG4gICAgLy8gYmVhY2ggc2VjdGlvbnMgb24gdGhlIGJlYWNobGluZSwgc2luY2UgdGhleSBvYnZpb3VzbHkgYXJlIHVuY29uc3RyYWluZWRcbiAgICAvLyBvbiB0aGVpciBsZWZ0L3JpZ2h0IHNpZGUuXG5cbiAgICAvLyBsb29rIGxlZnRcbiAgICB2YXIgbEFyYyA9IHByZXZpb3VzO1xuICAgIHdoaWxlIChsQXJjLmNpcmNsZUV2ZW50ICYmIGFic19mbih4LWxBcmMuY2lyY2xlRXZlbnQueCk8MWUtOSAmJiBhYnNfZm4oeS1sQXJjLmNpcmNsZUV2ZW50LnljZW50ZXIpPDFlLTkpIHtcbiAgICAgICAgcHJldmlvdXMgPSBsQXJjLnJiUHJldmlvdXM7XG4gICAgICAgIGRpc2FwcGVhcmluZ1RyYW5zaXRpb25zLnVuc2hpZnQobEFyYyk7XG4gICAgICAgIHRoaXMuZGV0YWNoQmVhY2hzZWN0aW9uKGxBcmMpOyAvLyBtYXJrIGZvciByZXVzZVxuICAgICAgICBsQXJjID0gcHJldmlvdXM7XG4gICAgICAgIH1cbiAgICAvLyBldmVuIHRob3VnaCBpdCBpcyBub3QgZGlzYXBwZWFyaW5nLCBJIHdpbGwgYWxzbyBhZGQgdGhlIGJlYWNoIHNlY3Rpb25cbiAgICAvLyBpbW1lZGlhdGVseSB0byB0aGUgbGVmdCBvZiB0aGUgbGVmdC1tb3N0IGNvbGxhcHNlZCBiZWFjaCBzZWN0aW9uLCBmb3JcbiAgICAvLyBjb252ZW5pZW5jZSwgc2luY2Ugd2UgbmVlZCB0byByZWZlciB0byBpdCBsYXRlciBhcyB0aGlzIGJlYWNoIHNlY3Rpb25cbiAgICAvLyBpcyB0aGUgJ2xlZnQnIHNpdGUgb2YgYW4gZWRnZSBmb3Igd2hpY2ggYSBzdGFydCBwb2ludCBpcyBzZXQuXG4gICAgZGlzYXBwZWFyaW5nVHJhbnNpdGlvbnMudW5zaGlmdChsQXJjKTtcbiAgICB0aGlzLmRldGFjaENpcmNsZUV2ZW50KGxBcmMpO1xuXG4gICAgLy8gbG9vayByaWdodFxuICAgIHZhciByQXJjID0gbmV4dDtcbiAgICB3aGlsZSAockFyYy5jaXJjbGVFdmVudCAmJiBhYnNfZm4oeC1yQXJjLmNpcmNsZUV2ZW50LngpPDFlLTkgJiYgYWJzX2ZuKHktckFyYy5jaXJjbGVFdmVudC55Y2VudGVyKTwxZS05KSB7XG4gICAgICAgIG5leHQgPSByQXJjLnJiTmV4dDtcbiAgICAgICAgZGlzYXBwZWFyaW5nVHJhbnNpdGlvbnMucHVzaChyQXJjKTtcbiAgICAgICAgdGhpcy5kZXRhY2hCZWFjaHNlY3Rpb24ockFyYyk7IC8vIG1hcmsgZm9yIHJldXNlXG4gICAgICAgIHJBcmMgPSBuZXh0O1xuICAgICAgICB9XG4gICAgLy8gd2UgYWxzbyBoYXZlIHRvIGFkZCB0aGUgYmVhY2ggc2VjdGlvbiBpbW1lZGlhdGVseSB0byB0aGUgcmlnaHQgb2YgdGhlXG4gICAgLy8gcmlnaHQtbW9zdCBjb2xsYXBzZWQgYmVhY2ggc2VjdGlvbiwgc2luY2UgdGhlcmUgaXMgYWxzbyBhIGRpc2FwcGVhcmluZ1xuICAgIC8vIHRyYW5zaXRpb24gcmVwcmVzZW50aW5nIGFuIGVkZ2UncyBzdGFydCBwb2ludCBvbiBpdHMgbGVmdC5cbiAgICBkaXNhcHBlYXJpbmdUcmFuc2l0aW9ucy5wdXNoKHJBcmMpO1xuICAgIHRoaXMuZGV0YWNoQ2lyY2xlRXZlbnQockFyYyk7XG5cbiAgICAvLyB3YWxrIHRocm91Z2ggYWxsIHRoZSBkaXNhcHBlYXJpbmcgdHJhbnNpdGlvbnMgYmV0d2VlbiBiZWFjaCBzZWN0aW9ucyBhbmRcbiAgICAvLyBzZXQgdGhlIHN0YXJ0IHBvaW50IG9mIHRoZWlyIChpbXBsaWVkKSBlZGdlLlxuICAgIHZhciBuQXJjcyA9IGRpc2FwcGVhcmluZ1RyYW5zaXRpb25zLmxlbmd0aCxcbiAgICAgICAgaUFyYztcbiAgICBmb3IgKGlBcmM9MTsgaUFyYzxuQXJjczsgaUFyYysrKSB7XG4gICAgICAgIHJBcmMgPSBkaXNhcHBlYXJpbmdUcmFuc2l0aW9uc1tpQXJjXTtcbiAgICAgICAgbEFyYyA9IGRpc2FwcGVhcmluZ1RyYW5zaXRpb25zW2lBcmMtMV07XG4gICAgICAgIHRoaXMuc2V0RWRnZVN0YXJ0cG9pbnQockFyYy5lZGdlLCBsQXJjLnNpdGUsIHJBcmMuc2l0ZSwgdmVydGV4KTtcbiAgICAgICAgfVxuXG4gICAgLy8gY3JlYXRlIGEgbmV3IGVkZ2UgYXMgd2UgaGF2ZSBub3cgYSBuZXcgdHJhbnNpdGlvbiBiZXR3ZWVuXG4gICAgLy8gdHdvIGJlYWNoIHNlY3Rpb25zIHdoaWNoIHdlcmUgcHJldmlvdXNseSBub3QgYWRqYWNlbnQuXG4gICAgLy8gc2luY2UgdGhpcyBlZGdlIGFwcGVhcnMgYXMgYSBuZXcgdmVydGV4IGlzIGRlZmluZWQsIHRoZSB2ZXJ0ZXhcbiAgICAvLyBhY3R1YWxseSBkZWZpbmUgYW4gZW5kIHBvaW50IG9mIHRoZSBlZGdlIChyZWxhdGl2ZSB0byB0aGUgc2l0ZVxuICAgIC8vIG9uIHRoZSBsZWZ0KVxuICAgIGxBcmMgPSBkaXNhcHBlYXJpbmdUcmFuc2l0aW9uc1swXTtcbiAgICByQXJjID0gZGlzYXBwZWFyaW5nVHJhbnNpdGlvbnNbbkFyY3MtMV07XG4gICAgckFyYy5lZGdlID0gdGhpcy5jcmVhdGVFZGdlKGxBcmMuc2l0ZSwgckFyYy5zaXRlLCB1bmRlZmluZWQsIHZlcnRleCk7XG5cbiAgICAvLyBjcmVhdGUgY2lyY2xlIGV2ZW50cyBpZiBhbnkgZm9yIGJlYWNoIHNlY3Rpb25zIGxlZnQgaW4gdGhlIGJlYWNobGluZVxuICAgIC8vIGFkamFjZW50IHRvIGNvbGxhcHNlZCBzZWN0aW9uc1xuICAgIHRoaXMuYXR0YWNoQ2lyY2xlRXZlbnQobEFyYyk7XG4gICAgdGhpcy5hdHRhY2hDaXJjbGVFdmVudChyQXJjKTtcbiAgICB9O1xuXG5Wb3Jvbm9pLnByb3RvdHlwZS5hZGRCZWFjaHNlY3Rpb24gPSBmdW5jdGlvbihzaXRlKSB7XG4gICAgdmFyIHggPSBzaXRlLngsXG4gICAgICAgIGRpcmVjdHJpeCA9IHNpdGUueTtcblxuICAgIC8vIGZpbmQgdGhlIGxlZnQgYW5kIHJpZ2h0IGJlYWNoIHNlY3Rpb25zIHdoaWNoIHdpbGwgc3Vycm91bmQgdGhlIG5ld2x5XG4gICAgLy8gY3JlYXRlZCBiZWFjaCBzZWN0aW9uLlxuICAgIC8vIHJoaWxsIDIwMTEtMDYtMDE6IFRoaXMgbG9vcCBpcyBvbmUgb2YgdGhlIG1vc3Qgb2Z0ZW4gZXhlY3V0ZWQsXG4gICAgLy8gaGVuY2Ugd2UgZXhwYW5kIGluLXBsYWNlIHRoZSBjb21wYXJpc29uLWFnYWluc3QtZXBzaWxvbiBjYWxscy5cbiAgICB2YXIgbEFyYywgckFyYyxcbiAgICAgICAgZHhsLCBkeHIsXG4gICAgICAgIG5vZGUgPSB0aGlzLmJlYWNobGluZS5yb290O1xuXG4gICAgd2hpbGUgKG5vZGUpIHtcbiAgICAgICAgZHhsID0gdGhpcy5sZWZ0QnJlYWtQb2ludChub2RlLGRpcmVjdHJpeCkteDtcbiAgICAgICAgLy8geCBsZXNzVGhhbldpdGhFcHNpbG9uIHhsID0+IGZhbGxzIHNvbWV3aGVyZSBiZWZvcmUgdGhlIGxlZnQgZWRnZSBvZiB0aGUgYmVhY2hzZWN0aW9uXG4gICAgICAgIGlmIChkeGwgPiAxZS05KSB7XG4gICAgICAgICAgICAvLyB0aGlzIGNhc2Ugc2hvdWxkIG5ldmVyIGhhcHBlblxuICAgICAgICAgICAgLy8gaWYgKCFub2RlLnJiTGVmdCkge1xuICAgICAgICAgICAgLy8gICAgckFyYyA9IG5vZGUucmJMZWZ0O1xuICAgICAgICAgICAgLy8gICAgYnJlYWs7XG4gICAgICAgICAgICAvLyAgICB9XG4gICAgICAgICAgICBub2RlID0gbm9kZS5yYkxlZnQ7XG4gICAgICAgICAgICB9XG4gICAgICAgIGVsc2Uge1xuICAgICAgICAgICAgZHhyID0geC10aGlzLnJpZ2h0QnJlYWtQb2ludChub2RlLGRpcmVjdHJpeCk7XG4gICAgICAgICAgICAvLyB4IGdyZWF0ZXJUaGFuV2l0aEVwc2lsb24geHIgPT4gZmFsbHMgc29tZXdoZXJlIGFmdGVyIHRoZSByaWdodCBlZGdlIG9mIHRoZSBiZWFjaHNlY3Rpb25cbiAgICAgICAgICAgIGlmIChkeHIgPiAxZS05KSB7XG4gICAgICAgICAgICAgICAgaWYgKCFub2RlLnJiUmlnaHQpIHtcbiAgICAgICAgICAgICAgICAgICAgbEFyYyA9IG5vZGU7XG4gICAgICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgbm9kZSA9IG5vZGUucmJSaWdodDtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICBlbHNlIHtcbiAgICAgICAgICAgICAgICAvLyB4IGVxdWFsV2l0aEVwc2lsb24geGwgPT4gZmFsbHMgZXhhY3RseSBvbiB0aGUgbGVmdCBlZGdlIG9mIHRoZSBiZWFjaHNlY3Rpb25cbiAgICAgICAgICAgICAgICBpZiAoZHhsID4gLTFlLTkpIHtcbiAgICAgICAgICAgICAgICAgICAgbEFyYyA9IG5vZGUucmJQcmV2aW91cztcbiAgICAgICAgICAgICAgICAgICAgckFyYyA9IG5vZGU7XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAvLyB4IGVxdWFsV2l0aEVwc2lsb24geHIgPT4gZmFsbHMgZXhhY3RseSBvbiB0aGUgcmlnaHQgZWRnZSBvZiB0aGUgYmVhY2hzZWN0aW9uXG4gICAgICAgICAgICAgICAgZWxzZSBpZiAoZHhyID4gLTFlLTkpIHtcbiAgICAgICAgICAgICAgICAgICAgbEFyYyA9IG5vZGU7XG4gICAgICAgICAgICAgICAgICAgIHJBcmMgPSBub2RlLnJiTmV4dDtcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIC8vIGZhbGxzIGV4YWN0bHkgc29tZXdoZXJlIGluIHRoZSBtaWRkbGUgb2YgdGhlIGJlYWNoc2VjdGlvblxuICAgICAgICAgICAgICAgIGVsc2Uge1xuICAgICAgICAgICAgICAgICAgICBsQXJjID0gckFyYyA9IG5vZGU7XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAvLyBhdCB0aGlzIHBvaW50LCBrZWVwIGluIG1pbmQgdGhhdCBsQXJjIGFuZC9vciByQXJjIGNvdWxkIGJlXG4gICAgLy8gdW5kZWZpbmVkIG9yIG51bGwuXG5cbiAgICAvLyBjcmVhdGUgYSBuZXcgYmVhY2ggc2VjdGlvbiBvYmplY3QgZm9yIHRoZSBzaXRlIGFuZCBhZGQgaXQgdG8gUkItdHJlZVxuICAgIHZhciBuZXdBcmMgPSB0aGlzLmNyZWF0ZUJlYWNoc2VjdGlvbihzaXRlKTtcbiAgICB0aGlzLmJlYWNobGluZS5yYkluc2VydFN1Y2Nlc3NvcihsQXJjLCBuZXdBcmMpO1xuXG4gICAgLy8gY2FzZXM6XG4gICAgLy9cblxuICAgIC8vIFtudWxsLG51bGxdXG4gICAgLy8gbGVhc3QgbGlrZWx5IGNhc2U6IG5ldyBiZWFjaCBzZWN0aW9uIGlzIHRoZSBmaXJzdCBiZWFjaCBzZWN0aW9uIG9uIHRoZVxuICAgIC8vIGJlYWNobGluZS5cbiAgICAvLyBUaGlzIGNhc2UgbWVhbnM6XG4gICAgLy8gICBubyBuZXcgdHJhbnNpdGlvbiBhcHBlYXJzXG4gICAgLy8gICBubyBjb2xsYXBzaW5nIGJlYWNoIHNlY3Rpb25cbiAgICAvLyAgIG5ldyBiZWFjaHNlY3Rpb24gYmVjb21lIHJvb3Qgb2YgdGhlIFJCLXRyZWVcbiAgICBpZiAoIWxBcmMgJiYgIXJBcmMpIHtcbiAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG5cbiAgICAvLyBbbEFyYyxyQXJjXSB3aGVyZSBsQXJjID09IHJBcmNcbiAgICAvLyBtb3N0IGxpa2VseSBjYXNlOiBuZXcgYmVhY2ggc2VjdGlvbiBzcGxpdCBhbiBleGlzdGluZyBiZWFjaFxuICAgIC8vIHNlY3Rpb24uXG4gICAgLy8gVGhpcyBjYXNlIG1lYW5zOlxuICAgIC8vICAgb25lIG5ldyB0cmFuc2l0aW9uIGFwcGVhcnNcbiAgICAvLyAgIHRoZSBsZWZ0IGFuZCByaWdodCBiZWFjaCBzZWN0aW9uIG1pZ2h0IGJlIGNvbGxhcHNpbmcgYXMgYSByZXN1bHRcbiAgICAvLyAgIHR3byBuZXcgbm9kZXMgYWRkZWQgdG8gdGhlIFJCLXRyZWVcbiAgICBpZiAobEFyYyA9PT0gckFyYykge1xuICAgICAgICAvLyBpbnZhbGlkYXRlIGNpcmNsZSBldmVudCBvZiBzcGxpdCBiZWFjaCBzZWN0aW9uXG4gICAgICAgIHRoaXMuZGV0YWNoQ2lyY2xlRXZlbnQobEFyYyk7XG5cbiAgICAgICAgLy8gc3BsaXQgdGhlIGJlYWNoIHNlY3Rpb24gaW50byB0d28gc2VwYXJhdGUgYmVhY2ggc2VjdGlvbnNcbiAgICAgICAgckFyYyA9IHRoaXMuY3JlYXRlQmVhY2hzZWN0aW9uKGxBcmMuc2l0ZSk7XG4gICAgICAgIHRoaXMuYmVhY2hsaW5lLnJiSW5zZXJ0U3VjY2Vzc29yKG5ld0FyYywgckFyYyk7XG5cbiAgICAgICAgLy8gc2luY2Ugd2UgaGF2ZSBhIG5ldyB0cmFuc2l0aW9uIGJldHdlZW4gdHdvIGJlYWNoIHNlY3Rpb25zLFxuICAgICAgICAvLyBhIG5ldyBlZGdlIGlzIGJvcm5cbiAgICAgICAgbmV3QXJjLmVkZ2UgPSByQXJjLmVkZ2UgPSB0aGlzLmNyZWF0ZUVkZ2UobEFyYy5zaXRlLCBuZXdBcmMuc2l0ZSk7XG5cbiAgICAgICAgLy8gY2hlY2sgd2hldGhlciB0aGUgbGVmdCBhbmQgcmlnaHQgYmVhY2ggc2VjdGlvbnMgYXJlIGNvbGxhcHNpbmdcbiAgICAgICAgLy8gYW5kIGlmIHNvIGNyZWF0ZSBjaXJjbGUgZXZlbnRzLCB0byBiZSBub3RpZmllZCB3aGVuIHRoZSBwb2ludCBvZlxuICAgICAgICAvLyBjb2xsYXBzZSBpcyByZWFjaGVkLlxuICAgICAgICB0aGlzLmF0dGFjaENpcmNsZUV2ZW50KGxBcmMpO1xuICAgICAgICB0aGlzLmF0dGFjaENpcmNsZUV2ZW50KHJBcmMpO1xuICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgIC8vIFtsQXJjLG51bGxdXG4gICAgLy8gZXZlbiBsZXNzIGxpa2VseSBjYXNlOiBuZXcgYmVhY2ggc2VjdGlvbiBpcyB0aGUgKmxhc3QqIGJlYWNoIHNlY3Rpb25cbiAgICAvLyBvbiB0aGUgYmVhY2hsaW5lIC0tIHRoaXMgY2FuIGhhcHBlbiAqb25seSogaWYgKmFsbCogdGhlIHByZXZpb3VzIGJlYWNoXG4gICAgLy8gc2VjdGlvbnMgY3VycmVudGx5IG9uIHRoZSBiZWFjaGxpbmUgc2hhcmUgdGhlIHNhbWUgeSB2YWx1ZSBhc1xuICAgIC8vIHRoZSBuZXcgYmVhY2ggc2VjdGlvbi5cbiAgICAvLyBUaGlzIGNhc2UgbWVhbnM6XG4gICAgLy8gICBvbmUgbmV3IHRyYW5zaXRpb24gYXBwZWFyc1xuICAgIC8vICAgbm8gY29sbGFwc2luZyBiZWFjaCBzZWN0aW9uIGFzIGEgcmVzdWx0XG4gICAgLy8gICBuZXcgYmVhY2ggc2VjdGlvbiBiZWNvbWUgcmlnaHQtbW9zdCBub2RlIG9mIHRoZSBSQi10cmVlXG4gICAgaWYgKGxBcmMgJiYgIXJBcmMpIHtcbiAgICAgICAgbmV3QXJjLmVkZ2UgPSB0aGlzLmNyZWF0ZUVkZ2UobEFyYy5zaXRlLG5ld0FyYy5zaXRlKTtcbiAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG5cbiAgICAvLyBbbnVsbCxyQXJjXVxuICAgIC8vIGltcG9zc2libGUgY2FzZTogYmVjYXVzZSBzaXRlcyBhcmUgc3RyaWN0bHkgcHJvY2Vzc2VkIGZyb20gdG9wIHRvIGJvdHRvbSxcbiAgICAvLyBhbmQgbGVmdCB0byByaWdodCwgd2hpY2ggZ3VhcmFudGVlcyB0aGF0IHRoZXJlIHdpbGwgYWx3YXlzIGJlIGEgYmVhY2ggc2VjdGlvblxuICAgIC8vIG9uIHRoZSBsZWZ0IC0tIGV4Y2VwdCBvZiBjb3Vyc2Ugd2hlbiB0aGVyZSBhcmUgbm8gYmVhY2ggc2VjdGlvbiBhdCBhbGwgb25cbiAgICAvLyB0aGUgYmVhY2ggbGluZSwgd2hpY2ggY2FzZSB3YXMgaGFuZGxlZCBhYm92ZS5cbiAgICAvLyByaGlsbCAyMDExLTA2LTAyOiBObyBwb2ludCB0ZXN0aW5nIGluIG5vbi1kZWJ1ZyB2ZXJzaW9uXG4gICAgLy9pZiAoIWxBcmMgJiYgckFyYykge1xuICAgIC8vICAgIHRocm93IFwiVm9yb25vaS5hZGRCZWFjaHNlY3Rpb24oKTogV2hhdCBpcyB0aGlzIEkgZG9uJ3QgZXZlblwiO1xuICAgIC8vICAgIH1cblxuICAgIC8vIFtsQXJjLHJBcmNdIHdoZXJlIGxBcmMgIT0gckFyY1xuICAgIC8vIHNvbWV3aGF0IGxlc3MgbGlrZWx5IGNhc2U6IG5ldyBiZWFjaCBzZWN0aW9uIGZhbGxzICpleGFjdGx5KiBpbiBiZXR3ZWVuIHR3b1xuICAgIC8vIGV4aXN0aW5nIGJlYWNoIHNlY3Rpb25zXG4gICAgLy8gVGhpcyBjYXNlIG1lYW5zOlxuICAgIC8vICAgb25lIHRyYW5zaXRpb24gZGlzYXBwZWFyc1xuICAgIC8vICAgdHdvIG5ldyB0cmFuc2l0aW9ucyBhcHBlYXJcbiAgICAvLyAgIHRoZSBsZWZ0IGFuZCByaWdodCBiZWFjaCBzZWN0aW9uIG1pZ2h0IGJlIGNvbGxhcHNpbmcgYXMgYSByZXN1bHRcbiAgICAvLyAgIG9ubHkgb25lIG5ldyBub2RlIGFkZGVkIHRvIHRoZSBSQi10cmVlXG4gICAgaWYgKGxBcmMgIT09IHJBcmMpIHtcbiAgICAgICAgLy8gaW52YWxpZGF0ZSBjaXJjbGUgZXZlbnRzIG9mIGxlZnQgYW5kIHJpZ2h0IHNpdGVzXG4gICAgICAgIHRoaXMuZGV0YWNoQ2lyY2xlRXZlbnQobEFyYyk7XG4gICAgICAgIHRoaXMuZGV0YWNoQ2lyY2xlRXZlbnQockFyYyk7XG5cbiAgICAgICAgLy8gYW4gZXhpc3RpbmcgdHJhbnNpdGlvbiBkaXNhcHBlYXJzLCBtZWFuaW5nIGEgdmVydGV4IGlzIGRlZmluZWQgYXRcbiAgICAgICAgLy8gdGhlIGRpc2FwcGVhcmFuY2UgcG9pbnQuXG4gICAgICAgIC8vIHNpbmNlIHRoZSBkaXNhcHBlYXJhbmNlIGlzIGNhdXNlZCBieSB0aGUgbmV3IGJlYWNoc2VjdGlvbiwgdGhlXG4gICAgICAgIC8vIHZlcnRleCBpcyBhdCB0aGUgY2VudGVyIG9mIHRoZSBjaXJjdW1zY3JpYmVkIGNpcmNsZSBvZiB0aGUgbGVmdCxcbiAgICAgICAgLy8gbmV3IGFuZCByaWdodCBiZWFjaHNlY3Rpb25zLlxuICAgICAgICAvLyBodHRwOi8vbWF0aGZvcnVtLm9yZy9saWJyYXJ5L2RybWF0aC92aWV3LzU1MDAyLmh0bWxcbiAgICAgICAgLy8gRXhjZXB0IHRoYXQgSSBicmluZyB0aGUgb3JpZ2luIGF0IEEgdG8gc2ltcGxpZnlcbiAgICAgICAgLy8gY2FsY3VsYXRpb25cbiAgICAgICAgdmFyIGxTaXRlID0gbEFyYy5zaXRlLFxuICAgICAgICAgICAgYXggPSBsU2l0ZS54LFxuICAgICAgICAgICAgYXkgPSBsU2l0ZS55LFxuICAgICAgICAgICAgYng9c2l0ZS54LWF4LFxuICAgICAgICAgICAgYnk9c2l0ZS55LWF5LFxuICAgICAgICAgICAgclNpdGUgPSByQXJjLnNpdGUsXG4gICAgICAgICAgICBjeD1yU2l0ZS54LWF4LFxuICAgICAgICAgICAgY3k9clNpdGUueS1heSxcbiAgICAgICAgICAgIGQ9MiooYngqY3ktYnkqY3gpLFxuICAgICAgICAgICAgaGI9YngqYngrYnkqYnksXG4gICAgICAgICAgICBoYz1jeCpjeCtjeSpjeSxcbiAgICAgICAgICAgIHZlcnRleCA9IHRoaXMuY3JlYXRlVmVydGV4KChjeSpoYi1ieSpoYykvZCtheCwgKGJ4KmhjLWN4KmhiKS9kK2F5KTtcblxuICAgICAgICAvLyBvbmUgdHJhbnNpdGlvbiBkaXNhcHBlYXJcbiAgICAgICAgdGhpcy5zZXRFZGdlU3RhcnRwb2ludChyQXJjLmVkZ2UsIGxTaXRlLCByU2l0ZSwgdmVydGV4KTtcblxuICAgICAgICAvLyB0d28gbmV3IHRyYW5zaXRpb25zIGFwcGVhciBhdCB0aGUgbmV3IHZlcnRleCBsb2NhdGlvblxuICAgICAgICBuZXdBcmMuZWRnZSA9IHRoaXMuY3JlYXRlRWRnZShsU2l0ZSwgc2l0ZSwgdW5kZWZpbmVkLCB2ZXJ0ZXgpO1xuICAgICAgICByQXJjLmVkZ2UgPSB0aGlzLmNyZWF0ZUVkZ2Uoc2l0ZSwgclNpdGUsIHVuZGVmaW5lZCwgdmVydGV4KTtcblxuICAgICAgICAvLyBjaGVjayB3aGV0aGVyIHRoZSBsZWZ0IGFuZCByaWdodCBiZWFjaCBzZWN0aW9ucyBhcmUgY29sbGFwc2luZ1xuICAgICAgICAvLyBhbmQgaWYgc28gY3JlYXRlIGNpcmNsZSBldmVudHMsIHRvIGhhbmRsZSB0aGUgcG9pbnQgb2YgY29sbGFwc2UuXG4gICAgICAgIHRoaXMuYXR0YWNoQ2lyY2xlRXZlbnQobEFyYyk7XG4gICAgICAgIHRoaXMuYXR0YWNoQ2lyY2xlRXZlbnQockFyYyk7XG4gICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuICAgIH07XG5cbi8vIC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLVxuLy8gQ2lyY2xlIGV2ZW50IG1ldGhvZHNcblxuLy8gcmhpbGwgMjAxMS0wNi0wNzogRm9yIHNvbWUgcmVhc29ucywgcGVyZm9ybWFuY2Ugc3VmZmVycyBzaWduaWZpY2FudGx5XG4vLyB3aGVuIGluc3RhbmNpYXRpbmcgYSBsaXRlcmFsIG9iamVjdCBpbnN0ZWFkIG9mIGFuIGVtcHR5IGN0b3JcblZvcm9ub2kucHJvdG90eXBlLkNpcmNsZUV2ZW50ID0gZnVuY3Rpb24oKSB7XG4gICAgLy8gcmhpbGwgMjAxMy0xMC0xMjogaXQgaGVscHMgdG8gc3RhdGUgZXhhY3RseSB3aGF0IHdlIGFyZSBhdCBjdG9yIHRpbWUuXG4gICAgdGhpcy5hcmMgPSBudWxsO1xuICAgIHRoaXMucmJMZWZ0ID0gbnVsbDtcbiAgICB0aGlzLnJiTmV4dCA9IG51bGw7XG4gICAgdGhpcy5yYlBhcmVudCA9IG51bGw7XG4gICAgdGhpcy5yYlByZXZpb3VzID0gbnVsbDtcbiAgICB0aGlzLnJiUmVkID0gZmFsc2U7XG4gICAgdGhpcy5yYlJpZ2h0ID0gbnVsbDtcbiAgICB0aGlzLnNpdGUgPSBudWxsO1xuICAgIHRoaXMueCA9IHRoaXMueSA9IHRoaXMueWNlbnRlciA9IDA7XG4gICAgfTtcblxuVm9yb25vaS5wcm90b3R5cGUuYXR0YWNoQ2lyY2xlRXZlbnQgPSBmdW5jdGlvbihhcmMpIHtcbiAgICB2YXIgbEFyYyA9IGFyYy5yYlByZXZpb3VzLFxuICAgICAgICByQXJjID0gYXJjLnJiTmV4dDtcbiAgICBpZiAoIWxBcmMgfHwgIXJBcmMpIHtyZXR1cm47fSAvLyBkb2VzIHRoYXQgZXZlciBoYXBwZW4/XG4gICAgdmFyIGxTaXRlID0gbEFyYy5zaXRlLFxuICAgICAgICBjU2l0ZSA9IGFyYy5zaXRlLFxuICAgICAgICByU2l0ZSA9IHJBcmMuc2l0ZTtcblxuICAgIC8vIElmIHNpdGUgb2YgbGVmdCBiZWFjaHNlY3Rpb24gaXMgc2FtZSBhcyBzaXRlIG9mXG4gICAgLy8gcmlnaHQgYmVhY2hzZWN0aW9uLCB0aGVyZSBjYW4ndCBiZSBjb252ZXJnZW5jZVxuICAgIGlmIChsU2l0ZT09PXJTaXRlKSB7cmV0dXJuO31cblxuICAgIC8vIEZpbmQgdGhlIGNpcmN1bXNjcmliZWQgY2lyY2xlIGZvciB0aGUgdGhyZWUgc2l0ZXMgYXNzb2NpYXRlZFxuICAgIC8vIHdpdGggdGhlIGJlYWNoc2VjdGlvbiB0cmlwbGV0LlxuICAgIC8vIHJoaWxsIDIwMTEtMDUtMjY6IEl0IGlzIG1vcmUgZWZmaWNpZW50IHRvIGNhbGN1bGF0ZSBpbi1wbGFjZVxuICAgIC8vIHJhdGhlciB0aGFuIGdldHRpbmcgdGhlIHJlc3VsdGluZyBjaXJjdW1zY3JpYmVkIGNpcmNsZSBmcm9tIGFuXG4gICAgLy8gb2JqZWN0IHJldHVybmVkIGJ5IGNhbGxpbmcgVm9yb25vaS5jaXJjdW1jaXJjbGUoKVxuICAgIC8vIGh0dHA6Ly9tYXRoZm9ydW0ub3JnL2xpYnJhcnkvZHJtYXRoL3ZpZXcvNTUwMDIuaHRtbFxuICAgIC8vIEV4Y2VwdCB0aGF0IEkgYnJpbmcgdGhlIG9yaWdpbiBhdCBjU2l0ZSB0byBzaW1wbGlmeSBjYWxjdWxhdGlvbnMuXG4gICAgLy8gVGhlIGJvdHRvbS1tb3N0IHBhcnQgb2YgdGhlIGNpcmN1bWNpcmNsZSBpcyBvdXIgRm9ydHVuZSAnY2lyY2xlXG4gICAgLy8gZXZlbnQnLCBhbmQgaXRzIGNlbnRlciBpcyBhIHZlcnRleCBwb3RlbnRpYWxseSBwYXJ0IG9mIHRoZSBmaW5hbFxuICAgIC8vIFZvcm9ub2kgZGlhZ3JhbS5cbiAgICB2YXIgYnggPSBjU2l0ZS54LFxuICAgICAgICBieSA9IGNTaXRlLnksXG4gICAgICAgIGF4ID0gbFNpdGUueC1ieCxcbiAgICAgICAgYXkgPSBsU2l0ZS55LWJ5LFxuICAgICAgICBjeCA9IHJTaXRlLngtYngsXG4gICAgICAgIGN5ID0gclNpdGUueS1ieTtcblxuICAgIC8vIElmIHBvaW50cyBsLT5jLT5yIGFyZSBjbG9ja3dpc2UsIHRoZW4gY2VudGVyIGJlYWNoIHNlY3Rpb24gZG9lcyBub3RcbiAgICAvLyBjb2xsYXBzZSwgaGVuY2UgaXQgY2FuJ3QgZW5kIHVwIGFzIGEgdmVydGV4ICh3ZSByZXVzZSAnZCcgaGVyZSwgd2hpY2hcbiAgICAvLyBzaWduIGlzIHJldmVyc2Ugb2YgdGhlIG9yaWVudGF0aW9uLCBoZW5jZSB3ZSByZXZlcnNlIHRoZSB0ZXN0LlxuICAgIC8vIGh0dHA6Ly9lbi53aWtpcGVkaWEub3JnL3dpa2kvQ3VydmVfb3JpZW50YXRpb24jT3JpZW50YXRpb25fb2ZfYV9zaW1wbGVfcG9seWdvblxuICAgIC8vIHJoaWxsIDIwMTEtMDUtMjE6IE5hc3R5IGZpbml0ZSBwcmVjaXNpb24gZXJyb3Igd2hpY2ggY2F1c2VkIGNpcmN1bWNpcmNsZSgpIHRvXG4gICAgLy8gcmV0dXJuIGluZmluaXRlczogMWUtMTIgc2VlbXMgdG8gZml4IHRoZSBwcm9ibGVtLlxuICAgIHZhciBkID0gMiooYXgqY3ktYXkqY3gpO1xuICAgIGlmIChkID49IC0yZS0xMil7cmV0dXJuO31cblxuICAgIHZhciBoYSA9IGF4KmF4K2F5KmF5LFxuICAgICAgICBoYyA9IGN4KmN4K2N5KmN5LFxuICAgICAgICB4ID0gKGN5KmhhLWF5KmhjKS9kLFxuICAgICAgICB5ID0gKGF4KmhjLWN4KmhhKS9kLFxuICAgICAgICB5Y2VudGVyID0geStieTtcblxuICAgIC8vIEltcG9ydGFudDogeWJvdHRvbSBzaG91bGQgYWx3YXlzIGJlIHVuZGVyIG9yIGF0IHN3ZWVwLCBzbyBubyBuZWVkXG4gICAgLy8gdG8gd2FzdGUgQ1BVIGN5Y2xlcyBieSBjaGVja2luZ1xuXG4gICAgLy8gcmVjeWNsZSBjaXJjbGUgZXZlbnQgb2JqZWN0IGlmIHBvc3NpYmxlXG4gICAgdmFyIGNpcmNsZUV2ZW50ID0gdGhpcy5jaXJjbGVFdmVudEp1bmt5YXJkLnBvcCgpO1xuICAgIGlmICghY2lyY2xlRXZlbnQpIHtcbiAgICAgICAgY2lyY2xlRXZlbnQgPSBuZXcgdGhpcy5DaXJjbGVFdmVudCgpO1xuICAgICAgICB9XG4gICAgY2lyY2xlRXZlbnQuYXJjID0gYXJjO1xuICAgIGNpcmNsZUV2ZW50LnNpdGUgPSBjU2l0ZTtcbiAgICBjaXJjbGVFdmVudC54ID0geCtieDtcbiAgICBjaXJjbGVFdmVudC55ID0geWNlbnRlcit0aGlzLnNxcnQoeCp4K3kqeSk7IC8vIHkgYm90dG9tXG4gICAgY2lyY2xlRXZlbnQueWNlbnRlciA9IHljZW50ZXI7XG4gICAgYXJjLmNpcmNsZUV2ZW50ID0gY2lyY2xlRXZlbnQ7XG5cbiAgICAvLyBmaW5kIGluc2VydGlvbiBwb2ludCBpbiBSQi10cmVlOiBjaXJjbGUgZXZlbnRzIGFyZSBvcmRlcmVkIGZyb21cbiAgICAvLyBzbWFsbGVzdCB0byBsYXJnZXN0XG4gICAgdmFyIHByZWRlY2Vzc29yID0gbnVsbCxcbiAgICAgICAgbm9kZSA9IHRoaXMuY2lyY2xlRXZlbnRzLnJvb3Q7XG4gICAgd2hpbGUgKG5vZGUpIHtcbiAgICAgICAgaWYgKGNpcmNsZUV2ZW50LnkgPCBub2RlLnkgfHwgKGNpcmNsZUV2ZW50LnkgPT09IG5vZGUueSAmJiBjaXJjbGVFdmVudC54IDw9IG5vZGUueCkpIHtcbiAgICAgICAgICAgIGlmIChub2RlLnJiTGVmdCkge1xuICAgICAgICAgICAgICAgIG5vZGUgPSBub2RlLnJiTGVmdDtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICBlbHNlIHtcbiAgICAgICAgICAgICAgICBwcmVkZWNlc3NvciA9IG5vZGUucmJQcmV2aW91cztcbiAgICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgIGVsc2Uge1xuICAgICAgICAgICAgaWYgKG5vZGUucmJSaWdodCkge1xuICAgICAgICAgICAgICAgIG5vZGUgPSBub2RlLnJiUmlnaHQ7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgZWxzZSB7XG4gICAgICAgICAgICAgICAgcHJlZGVjZXNzb3IgPSBub2RlO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgIHRoaXMuY2lyY2xlRXZlbnRzLnJiSW5zZXJ0U3VjY2Vzc29yKHByZWRlY2Vzc29yLCBjaXJjbGVFdmVudCk7XG4gICAgaWYgKCFwcmVkZWNlc3Nvcikge1xuICAgICAgICB0aGlzLmZpcnN0Q2lyY2xlRXZlbnQgPSBjaXJjbGVFdmVudDtcbiAgICAgICAgfVxuICAgIH07XG5cblZvcm9ub2kucHJvdG90eXBlLmRldGFjaENpcmNsZUV2ZW50ID0gZnVuY3Rpb24oYXJjKSB7XG4gICAgdmFyIGNpcmNsZUV2ZW50ID0gYXJjLmNpcmNsZUV2ZW50O1xuICAgIGlmIChjaXJjbGVFdmVudCkge1xuICAgICAgICBpZiAoIWNpcmNsZUV2ZW50LnJiUHJldmlvdXMpIHtcbiAgICAgICAgICAgIHRoaXMuZmlyc3RDaXJjbGVFdmVudCA9IGNpcmNsZUV2ZW50LnJiTmV4dDtcbiAgICAgICAgICAgIH1cbiAgICAgICAgdGhpcy5jaXJjbGVFdmVudHMucmJSZW1vdmVOb2RlKGNpcmNsZUV2ZW50KTsgLy8gcmVtb3ZlIGZyb20gUkItdHJlZVxuICAgICAgICB0aGlzLmNpcmNsZUV2ZW50SnVua3lhcmQucHVzaChjaXJjbGVFdmVudCk7XG4gICAgICAgIGFyYy5jaXJjbGVFdmVudCA9IG51bGw7XG4gICAgICAgIH1cbiAgICB9O1xuXG4vLyAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS1cbi8vIERpYWdyYW0gY29tcGxldGlvbiBtZXRob2RzXG5cbi8vIGNvbm5lY3QgZGFuZ2xpbmcgZWRnZXMgKG5vdCBpZiBhIGN1cnNvcnkgdGVzdCB0ZWxscyB1c1xuLy8gaXQgaXMgbm90IGdvaW5nIHRvIGJlIHZpc2libGUuXG4vLyByZXR1cm4gdmFsdWU6XG4vLyAgIGZhbHNlOiB0aGUgZGFuZ2xpbmcgZW5kcG9pbnQgY291bGRuJ3QgYmUgY29ubmVjdGVkXG4vLyAgIHRydWU6IHRoZSBkYW5nbGluZyBlbmRwb2ludCBjb3VsZCBiZSBjb25uZWN0ZWRcblZvcm9ub2kucHJvdG90eXBlLmNvbm5lY3RFZGdlID0gZnVuY3Rpb24oZWRnZSwgYmJveCkge1xuICAgIC8vIHNraXAgaWYgZW5kIHBvaW50IGFscmVhZHkgY29ubmVjdGVkXG4gICAgdmFyIHZiID0gZWRnZS52YjtcbiAgICBpZiAoISF2Yikge3JldHVybiB0cnVlO31cblxuICAgIC8vIG1ha2UgbG9jYWwgY29weSBmb3IgcGVyZm9ybWFuY2UgcHVycG9zZVxuICAgIHZhciB2YSA9IGVkZ2UudmEsXG4gICAgICAgIHhsID0gYmJveC54bCxcbiAgICAgICAgeHIgPSBiYm94LnhyLFxuICAgICAgICB5dCA9IGJib3gueXQsXG4gICAgICAgIHliID0gYmJveC55YixcbiAgICAgICAgbFNpdGUgPSBlZGdlLmxTaXRlLFxuICAgICAgICByU2l0ZSA9IGVkZ2UuclNpdGUsXG4gICAgICAgIGx4ID0gbFNpdGUueCxcbiAgICAgICAgbHkgPSBsU2l0ZS55LFxuICAgICAgICByeCA9IHJTaXRlLngsXG4gICAgICAgIHJ5ID0gclNpdGUueSxcbiAgICAgICAgZnggPSAobHgrcngpLzIsXG4gICAgICAgIGZ5ID0gKGx5K3J5KS8yLFxuICAgICAgICBmbSwgZmI7XG5cbiAgICAvLyBpZiB3ZSByZWFjaCBoZXJlLCB0aGlzIG1lYW5zIGNlbGxzIHdoaWNoIHVzZSB0aGlzIGVkZ2Ugd2lsbCBuZWVkXG4gICAgLy8gdG8gYmUgY2xvc2VkLCB3aGV0aGVyIGJlY2F1c2UgdGhlIGVkZ2Ugd2FzIHJlbW92ZWQsIG9yIGJlY2F1c2UgaXRcbiAgICAvLyB3YXMgY29ubmVjdGVkIHRvIHRoZSBib3VuZGluZyBib3guXG4gICAgdGhpcy5jZWxsc1tsU2l0ZS52b3Jvbm9pSWRdLmNsb3NlTWUgPSB0cnVlO1xuICAgIHRoaXMuY2VsbHNbclNpdGUudm9yb25vaUlkXS5jbG9zZU1lID0gdHJ1ZTtcblxuICAgIC8vIGdldCB0aGUgbGluZSBlcXVhdGlvbiBvZiB0aGUgYmlzZWN0b3IgaWYgbGluZSBpcyBub3QgdmVydGljYWxcbiAgICBpZiAocnkgIT09IGx5KSB7XG4gICAgICAgIGZtID0gKGx4LXJ4KS8ocnktbHkpO1xuICAgICAgICBmYiA9IGZ5LWZtKmZ4O1xuICAgICAgICB9XG5cbiAgICAvLyByZW1lbWJlciwgZGlyZWN0aW9uIG9mIGxpbmUgKHJlbGF0aXZlIHRvIGxlZnQgc2l0ZSk6XG4gICAgLy8gdXB3YXJkOiBsZWZ0LnggPCByaWdodC54XG4gICAgLy8gZG93bndhcmQ6IGxlZnQueCA+IHJpZ2h0LnhcbiAgICAvLyBob3Jpem9udGFsOiBsZWZ0LnggPT0gcmlnaHQueFxuICAgIC8vIHVwd2FyZDogbGVmdC54IDwgcmlnaHQueFxuICAgIC8vIHJpZ2h0d2FyZDogbGVmdC55IDwgcmlnaHQueVxuICAgIC8vIGxlZnR3YXJkOiBsZWZ0LnkgPiByaWdodC55XG4gICAgLy8gdmVydGljYWw6IGxlZnQueSA9PSByaWdodC55XG5cbiAgICAvLyBkZXBlbmRpbmcgb24gdGhlIGRpcmVjdGlvbiwgZmluZCB0aGUgYmVzdCBzaWRlIG9mIHRoZVxuICAgIC8vIGJvdW5kaW5nIGJveCB0byB1c2UgdG8gZGV0ZXJtaW5lIGEgcmVhc29uYWJsZSBzdGFydCBwb2ludFxuXG4gICAgLy8gcmhpbGwgMjAxMy0xMi0wMjpcbiAgICAvLyBXaGlsZSBhdCBpdCwgc2luY2Ugd2UgaGF2ZSB0aGUgdmFsdWVzIHdoaWNoIGRlZmluZSB0aGUgbGluZSxcbiAgICAvLyBjbGlwIHRoZSBlbmQgb2YgdmEgaWYgaXQgaXMgb3V0c2lkZSB0aGUgYmJveC5cbiAgICAvLyBodHRwczovL2dpdGh1Yi5jb20vZ29yaGlsbC9KYXZhc2NyaXB0LVZvcm9ub2kvaXNzdWVzLzE1XG4gICAgLy8gVE9ETzogRG8gYWxsIHRoZSBjbGlwcGluZyBoZXJlIHJhdGhlciB0aGFuIHJlbHkgb24gTGlhbmctQmFyc2t5XG4gICAgLy8gd2hpY2ggZG9lcyBub3QgZG8gd2VsbCBzb21ldGltZXMgZHVlIHRvIGxvc3Mgb2YgYXJpdGhtZXRpY1xuICAgIC8vIHByZWNpc2lvbi4gVGhlIGNvZGUgaGVyZSBkb2Vzbid0IGRlZ3JhZGUgaWYgb25lIG9mIHRoZSB2ZXJ0ZXggaXNcbiAgICAvLyBhdCBhIGh1Z2UgZGlzdGFuY2UuXG5cbiAgICAvLyBzcGVjaWFsIGNhc2U6IHZlcnRpY2FsIGxpbmVcbiAgICBpZiAoZm0gPT09IHVuZGVmaW5lZCkge1xuICAgICAgICAvLyBkb2Vzbid0IGludGVyc2VjdCB3aXRoIHZpZXdwb3J0XG4gICAgICAgIGlmIChmeCA8IHhsIHx8IGZ4ID49IHhyKSB7cmV0dXJuIGZhbHNlO31cbiAgICAgICAgLy8gZG93bndhcmRcbiAgICAgICAgaWYgKGx4ID4gcngpIHtcbiAgICAgICAgICAgIGlmICghdmEgfHwgdmEueSA8IHl0KSB7XG4gICAgICAgICAgICAgICAgdmEgPSB0aGlzLmNyZWF0ZVZlcnRleChmeCwgeXQpO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGVsc2UgaWYgKHZhLnkgPj0geWIpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgdmIgPSB0aGlzLmNyZWF0ZVZlcnRleChmeCwgeWIpO1xuICAgICAgICAgICAgfVxuICAgICAgICAvLyB1cHdhcmRcbiAgICAgICAgZWxzZSB7XG4gICAgICAgICAgICBpZiAoIXZhIHx8IHZhLnkgPiB5Yikge1xuICAgICAgICAgICAgICAgIHZhID0gdGhpcy5jcmVhdGVWZXJ0ZXgoZngsIHliKTtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICBlbHNlIGlmICh2YS55IDwgeXQpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgdmIgPSB0aGlzLmNyZWF0ZVZlcnRleChmeCwgeXQpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgLy8gY2xvc2VyIHRvIHZlcnRpY2FsIHRoYW4gaG9yaXpvbnRhbCwgY29ubmVjdCBzdGFydCBwb2ludCB0byB0aGVcbiAgICAvLyB0b3Agb3IgYm90dG9tIHNpZGUgb2YgdGhlIGJvdW5kaW5nIGJveFxuICAgIGVsc2UgaWYgKGZtIDwgLTEgfHwgZm0gPiAxKSB7XG4gICAgICAgIC8vIGRvd253YXJkXG4gICAgICAgIGlmIChseCA+IHJ4KSB7XG4gICAgICAgICAgICBpZiAoIXZhIHx8IHZhLnkgPCB5dCkge1xuICAgICAgICAgICAgICAgIHZhID0gdGhpcy5jcmVhdGVWZXJ0ZXgoKHl0LWZiKS9mbSwgeXQpO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGVsc2UgaWYgKHZhLnkgPj0geWIpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgdmIgPSB0aGlzLmNyZWF0ZVZlcnRleCgoeWItZmIpL2ZtLCB5Yik7XG4gICAgICAgICAgICB9XG4gICAgICAgIC8vIHVwd2FyZFxuICAgICAgICBlbHNlIHtcbiAgICAgICAgICAgIGlmICghdmEgfHwgdmEueSA+IHliKSB7XG4gICAgICAgICAgICAgICAgdmEgPSB0aGlzLmNyZWF0ZVZlcnRleCgoeWItZmIpL2ZtLCB5Yik7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgZWxzZSBpZiAodmEueSA8IHl0KSB7XG4gICAgICAgICAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIHZiID0gdGhpcy5jcmVhdGVWZXJ0ZXgoKHl0LWZiKS9mbSwgeXQpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgLy8gY2xvc2VyIHRvIGhvcml6b250YWwgdGhhbiB2ZXJ0aWNhbCwgY29ubmVjdCBzdGFydCBwb2ludCB0byB0aGVcbiAgICAvLyBsZWZ0IG9yIHJpZ2h0IHNpZGUgb2YgdGhlIGJvdW5kaW5nIGJveFxuICAgIGVsc2Uge1xuICAgICAgICAvLyByaWdodHdhcmRcbiAgICAgICAgaWYgKGx5IDwgcnkpIHtcbiAgICAgICAgICAgIGlmICghdmEgfHwgdmEueCA8IHhsKSB7XG4gICAgICAgICAgICAgICAgdmEgPSB0aGlzLmNyZWF0ZVZlcnRleCh4bCwgZm0qeGwrZmIpO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGVsc2UgaWYgKHZhLnggPj0geHIpIHtcbiAgICAgICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgdmIgPSB0aGlzLmNyZWF0ZVZlcnRleCh4ciwgZm0qeHIrZmIpO1xuICAgICAgICAgICAgfVxuICAgICAgICAvLyBsZWZ0d2FyZFxuICAgICAgICBlbHNlIHtcbiAgICAgICAgICAgIGlmICghdmEgfHwgdmEueCA+IHhyKSB7XG4gICAgICAgICAgICAgICAgdmEgPSB0aGlzLmNyZWF0ZVZlcnRleCh4ciwgZm0qeHIrZmIpO1xuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGVsc2UgaWYgKHZhLnggPCB4bCkge1xuICAgICAgICAgICAgICAgIHJldHVybiBmYWxzZTtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB2YiA9IHRoaXMuY3JlYXRlVmVydGV4KHhsLCBmbSp4bCtmYik7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICBlZGdlLnZhID0gdmE7XG4gICAgZWRnZS52YiA9IHZiO1xuXG4gICAgcmV0dXJuIHRydWU7XG4gICAgfTtcblxuLy8gbGluZS1jbGlwcGluZyBjb2RlIHRha2VuIGZyb206XG4vLyAgIExpYW5nLUJhcnNreSBmdW5jdGlvbiBieSBEYW5pZWwgV2hpdGVcbi8vICAgaHR0cDovL3d3dy5za3l0b3BpYS5jb20vcHJvamVjdC9hcnRpY2xlcy9jb21wc2NpL2NsaXBwaW5nLmh0bWxcbi8vIFRoYW5rcyFcbi8vIEEgYml0IG1vZGlmaWVkIHRvIG1pbmltaXplIGNvZGUgcGF0aHNcblZvcm9ub2kucHJvdG90eXBlLmNsaXBFZGdlID0gZnVuY3Rpb24oZWRnZSwgYmJveCkge1xuICAgIHZhciBheCA9IGVkZ2UudmEueCxcbiAgICAgICAgYXkgPSBlZGdlLnZhLnksXG4gICAgICAgIGJ4ID0gZWRnZS52Yi54LFxuICAgICAgICBieSA9IGVkZ2UudmIueSxcbiAgICAgICAgdDAgPSAwLFxuICAgICAgICB0MSA9IDEsXG4gICAgICAgIGR4ID0gYngtYXgsXG4gICAgICAgIGR5ID0gYnktYXk7XG4gICAgLy8gbGVmdFxuICAgIHZhciBxID0gYXgtYmJveC54bDtcbiAgICBpZiAoZHg9PT0wICYmIHE8MCkge3JldHVybiBmYWxzZTt9XG4gICAgdmFyIHIgPSAtcS9keDtcbiAgICBpZiAoZHg8MCkge1xuICAgICAgICBpZiAocjx0MCkge3JldHVybiBmYWxzZTt9XG4gICAgICAgIGlmIChyPHQxKSB7dDE9cjt9XG4gICAgICAgIH1cbiAgICBlbHNlIGlmIChkeD4wKSB7XG4gICAgICAgIGlmIChyPnQxKSB7cmV0dXJuIGZhbHNlO31cbiAgICAgICAgaWYgKHI+dDApIHt0MD1yO31cbiAgICAgICAgfVxuICAgIC8vIHJpZ2h0XG4gICAgcSA9IGJib3gueHItYXg7XG4gICAgaWYgKGR4PT09MCAmJiBxPDApIHtyZXR1cm4gZmFsc2U7fVxuICAgIHIgPSBxL2R4O1xuICAgIGlmIChkeDwwKSB7XG4gICAgICAgIGlmIChyPnQxKSB7cmV0dXJuIGZhbHNlO31cbiAgICAgICAgaWYgKHI+dDApIHt0MD1yO31cbiAgICAgICAgfVxuICAgIGVsc2UgaWYgKGR4PjApIHtcbiAgICAgICAgaWYgKHI8dDApIHtyZXR1cm4gZmFsc2U7fVxuICAgICAgICBpZiAocjx0MSkge3QxPXI7fVxuICAgICAgICB9XG4gICAgLy8gdG9wXG4gICAgcSA9IGF5LWJib3gueXQ7XG4gICAgaWYgKGR5PT09MCAmJiBxPDApIHtyZXR1cm4gZmFsc2U7fVxuICAgIHIgPSAtcS9keTtcbiAgICBpZiAoZHk8MCkge1xuICAgICAgICBpZiAocjx0MCkge3JldHVybiBmYWxzZTt9XG4gICAgICAgIGlmIChyPHQxKSB7dDE9cjt9XG4gICAgICAgIH1cbiAgICBlbHNlIGlmIChkeT4wKSB7XG4gICAgICAgIGlmIChyPnQxKSB7cmV0dXJuIGZhbHNlO31cbiAgICAgICAgaWYgKHI+dDApIHt0MD1yO31cbiAgICAgICAgfVxuICAgIC8vIGJvdHRvbVxuICAgIHEgPSBiYm94LnliLWF5O1xuICAgIGlmIChkeT09PTAgJiYgcTwwKSB7cmV0dXJuIGZhbHNlO31cbiAgICByID0gcS9keTtcbiAgICBpZiAoZHk8MCkge1xuICAgICAgICBpZiAocj50MSkge3JldHVybiBmYWxzZTt9XG4gICAgICAgIGlmIChyPnQwKSB7dDA9cjt9XG4gICAgICAgIH1cbiAgICBlbHNlIGlmIChkeT4wKSB7XG4gICAgICAgIGlmIChyPHQwKSB7cmV0dXJuIGZhbHNlO31cbiAgICAgICAgaWYgKHI8dDEpIHt0MT1yO31cbiAgICAgICAgfVxuXG4gICAgLy8gaWYgd2UgcmVhY2ggdGhpcyBwb2ludCwgVm9yb25vaSBlZGdlIGlzIHdpdGhpbiBiYm94XG5cbiAgICAvLyBpZiB0MCA+IDAsIHZhIG5lZWRzIHRvIGNoYW5nZVxuICAgIC8vIHJoaWxsIDIwMTEtMDYtMDM6IHdlIG5lZWQgdG8gY3JlYXRlIGEgbmV3IHZlcnRleCByYXRoZXJcbiAgICAvLyB0aGFuIG1vZGlmeWluZyB0aGUgZXhpc3Rpbmcgb25lLCBzaW5jZSB0aGUgZXhpc3RpbmdcbiAgICAvLyBvbmUgaXMgbGlrZWx5IHNoYXJlZCB3aXRoIGF0IGxlYXN0IGFub3RoZXIgZWRnZVxuICAgIGlmICh0MCA+IDApIHtcbiAgICAgICAgZWRnZS52YSA9IHRoaXMuY3JlYXRlVmVydGV4KGF4K3QwKmR4LCBheSt0MCpkeSk7XG4gICAgICAgIH1cblxuICAgIC8vIGlmIHQxIDwgMSwgdmIgbmVlZHMgdG8gY2hhbmdlXG4gICAgLy8gcmhpbGwgMjAxMS0wNi0wMzogd2UgbmVlZCB0byBjcmVhdGUgYSBuZXcgdmVydGV4IHJhdGhlclxuICAgIC8vIHRoYW4gbW9kaWZ5aW5nIHRoZSBleGlzdGluZyBvbmUsIHNpbmNlIHRoZSBleGlzdGluZ1xuICAgIC8vIG9uZSBpcyBsaWtlbHkgc2hhcmVkIHdpdGggYXQgbGVhc3QgYW5vdGhlciBlZGdlXG4gICAgaWYgKHQxIDwgMSkge1xuICAgICAgICBlZGdlLnZiID0gdGhpcy5jcmVhdGVWZXJ0ZXgoYXgrdDEqZHgsIGF5K3QxKmR5KTtcbiAgICAgICAgfVxuXG4gICAgLy8gdmEgYW5kL29yIHZiIHdlcmUgY2xpcHBlZCwgdGh1cyB3ZSB3aWxsIG5lZWQgdG8gY2xvc2VcbiAgICAvLyBjZWxscyB3aGljaCB1c2UgdGhpcyBlZGdlLlxuICAgIGlmICggdDAgPiAwIHx8IHQxIDwgMSApIHtcbiAgICAgICAgdGhpcy5jZWxsc1tlZGdlLmxTaXRlLnZvcm9ub2lJZF0uY2xvc2VNZSA9IHRydWU7XG4gICAgICAgIHRoaXMuY2VsbHNbZWRnZS5yU2l0ZS52b3Jvbm9pSWRdLmNsb3NlTWUgPSB0cnVlO1xuICAgIH1cblxuICAgIHJldHVybiB0cnVlO1xuICAgIH07XG5cbi8vIENvbm5lY3QvY3V0IGVkZ2VzIGF0IGJvdW5kaW5nIGJveFxuVm9yb25vaS5wcm90b3R5cGUuY2xpcEVkZ2VzID0gZnVuY3Rpb24oYmJveCkge1xuICAgIC8vIGNvbm5lY3QgYWxsIGRhbmdsaW5nIGVkZ2VzIHRvIGJvdW5kaW5nIGJveFxuICAgIC8vIG9yIGdldCByaWQgb2YgdGhlbSBpZiBpdCBjYW4ndCBiZSBkb25lXG4gICAgdmFyIGVkZ2VzID0gdGhpcy5lZGdlcyxcbiAgICAgICAgaUVkZ2UgPSBlZGdlcy5sZW5ndGgsXG4gICAgICAgIGVkZ2UsXG4gICAgICAgIGFic19mbiA9IE1hdGguYWJzO1xuXG4gICAgLy8gaXRlcmF0ZSBiYWNrd2FyZCBzbyB3ZSBjYW4gc3BsaWNlIHNhZmVseVxuICAgIHdoaWxlIChpRWRnZS0tKSB7XG4gICAgICAgIGVkZ2UgPSBlZGdlc1tpRWRnZV07XG4gICAgICAgIC8vIGVkZ2UgaXMgcmVtb3ZlZCBpZjpcbiAgICAgICAgLy8gICBpdCBpcyB3aG9sbHkgb3V0c2lkZSB0aGUgYm91bmRpbmcgYm94XG4gICAgICAgIC8vICAgaXQgaXMgbG9va2luZyBtb3JlIGxpa2UgYSBwb2ludCB0aGFuIGEgbGluZVxuICAgICAgICBpZiAoIXRoaXMuY29ubmVjdEVkZ2UoZWRnZSwgYmJveCkgfHxcbiAgICAgICAgICAgICF0aGlzLmNsaXBFZGdlKGVkZ2UsIGJib3gpIHx8XG4gICAgICAgICAgICAoYWJzX2ZuKGVkZ2UudmEueC1lZGdlLnZiLngpPDFlLTkgJiYgYWJzX2ZuKGVkZ2UudmEueS1lZGdlLnZiLnkpPDFlLTkpKSB7XG4gICAgICAgICAgICBlZGdlLnZhID0gZWRnZS52YiA9IG51bGw7XG4gICAgICAgICAgICBlZGdlcy5zcGxpY2UoaUVkZ2UsMSk7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICB9O1xuXG4vLyBDbG9zZSB0aGUgY2VsbHMuXG4vLyBUaGUgY2VsbHMgYXJlIGJvdW5kIGJ5IHRoZSBzdXBwbGllZCBib3VuZGluZyBib3guXG4vLyBFYWNoIGNlbGwgcmVmZXJzIHRvIGl0cyBhc3NvY2lhdGVkIHNpdGUsIGFuZCBhIGxpc3Rcbi8vIG9mIGhhbGZlZGdlcyBvcmRlcmVkIGNvdW50ZXJjbG9ja3dpc2UuXG5Wb3Jvbm9pLnByb3RvdHlwZS5jbG9zZUNlbGxzID0gZnVuY3Rpb24oYmJveCkge1xuICAgIHZhciB4bCA9IGJib3gueGwsXG4gICAgICAgIHhyID0gYmJveC54cixcbiAgICAgICAgeXQgPSBiYm94Lnl0LFxuICAgICAgICB5YiA9IGJib3gueWIsXG4gICAgICAgIGNlbGxzID0gdGhpcy5jZWxscyxcbiAgICAgICAgaUNlbGwgPSBjZWxscy5sZW5ndGgsXG4gICAgICAgIGNlbGwsXG4gICAgICAgIGlMZWZ0LFxuICAgICAgICBoYWxmZWRnZXMsIG5IYWxmZWRnZXMsXG4gICAgICAgIGVkZ2UsXG4gICAgICAgIHZhLCB2YiwgdnosXG4gICAgICAgIGxhc3RCb3JkZXJTZWdtZW50LFxuICAgICAgICBhYnNfZm4gPSBNYXRoLmFicztcblxuICAgIHdoaWxlIChpQ2VsbC0tKSB7XG4gICAgICAgIGNlbGwgPSBjZWxsc1tpQ2VsbF07XG4gICAgICAgIC8vIHBydW5lLCBvcmRlciBoYWxmZWRnZXMgY291bnRlcmNsb2Nrd2lzZSwgdGhlbiBhZGQgbWlzc2luZyBvbmVzXG4gICAgICAgIC8vIHJlcXVpcmVkIHRvIGNsb3NlIGNlbGxzXG4gICAgICAgIGlmICghY2VsbC5wcmVwYXJlSGFsZmVkZ2VzKCkpIHtcbiAgICAgICAgICAgIGNvbnRpbnVlO1xuICAgICAgICAgICAgfVxuICAgICAgICBpZiAoIWNlbGwuY2xvc2VNZSkge1xuICAgICAgICAgICAgY29udGludWU7XG4gICAgICAgICAgICB9XG4gICAgICAgIC8vIGZpbmQgZmlyc3QgJ3VuY2xvc2VkJyBwb2ludC5cbiAgICAgICAgLy8gYW4gJ3VuY2xvc2VkJyBwb2ludCB3aWxsIGJlIHRoZSBlbmQgcG9pbnQgb2YgYSBoYWxmZWRnZSB3aGljaFxuICAgICAgICAvLyBkb2VzIG5vdCBtYXRjaCB0aGUgc3RhcnQgcG9pbnQgb2YgdGhlIGZvbGxvd2luZyBoYWxmZWRnZVxuICAgICAgICBoYWxmZWRnZXMgPSBjZWxsLmhhbGZlZGdlcztcbiAgICAgICAgbkhhbGZlZGdlcyA9IGhhbGZlZGdlcy5sZW5ndGg7XG4gICAgICAgIC8vIHNwZWNpYWwgY2FzZTogb25seSBvbmUgc2l0ZSwgaW4gd2hpY2ggY2FzZSwgdGhlIHZpZXdwb3J0IGlzIHRoZSBjZWxsXG4gICAgICAgIC8vIC4uLlxuXG4gICAgICAgIC8vIGFsbCBvdGhlciBjYXNlc1xuICAgICAgICBpTGVmdCA9IDA7XG4gICAgICAgIHdoaWxlIChpTGVmdCA8IG5IYWxmZWRnZXMpIHtcbiAgICAgICAgICAgIHZhID0gaGFsZmVkZ2VzW2lMZWZ0XS5nZXRFbmRwb2ludCgpO1xuICAgICAgICAgICAgdnogPSBoYWxmZWRnZXNbKGlMZWZ0KzEpICUgbkhhbGZlZGdlc10uZ2V0U3RhcnRwb2ludCgpO1xuICAgICAgICAgICAgLy8gaWYgZW5kIHBvaW50IGlzIG5vdCBlcXVhbCB0byBzdGFydCBwb2ludCwgd2UgbmVlZCB0byBhZGQgdGhlIG1pc3NpbmdcbiAgICAgICAgICAgIC8vIGhhbGZlZGdlKHMpIHVwIHRvIHZ6XG4gICAgICAgICAgICBpZiAoYWJzX2ZuKHZhLngtdnoueCk+PTFlLTkgfHwgYWJzX2ZuKHZhLnktdnoueSk+PTFlLTkpIHtcblxuICAgICAgICAgICAgICAgIC8vIHJoaWxsIDIwMTMtMTItMDI6XG4gICAgICAgICAgICAgICAgLy8gXCJIb2xlc1wiIGluIHRoZSBoYWxmZWRnZXMgYXJlIG5vdCBuZWNlc3NhcmlseSBhbHdheXMgYWRqYWNlbnQuXG4gICAgICAgICAgICAgICAgLy8gaHR0cHM6Ly9naXRodWIuY29tL2dvcmhpbGwvSmF2YXNjcmlwdC1Wb3Jvbm9pL2lzc3Vlcy8xNlxuXG4gICAgICAgICAgICAgICAgLy8gZmluZCBlbnRyeSBwb2ludDpcbiAgICAgICAgICAgICAgICBzd2l0Y2ggKHRydWUpIHtcblxuICAgICAgICAgICAgICAgICAgICAvLyB3YWxrIGRvd253YXJkIGFsb25nIGxlZnQgc2lkZVxuICAgICAgICAgICAgICAgICAgICBjYXNlIHRoaXMuZXF1YWxXaXRoRXBzaWxvbih2YS54LHhsKSAmJiB0aGlzLmxlc3NUaGFuV2l0aEVwc2lsb24odmEueSx5Yik6XG4gICAgICAgICAgICAgICAgICAgICAgICBsYXN0Qm9yZGVyU2VnbWVudCA9IHRoaXMuZXF1YWxXaXRoRXBzaWxvbih2ei54LHhsKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIHZiID0gdGhpcy5jcmVhdGVWZXJ0ZXgoeGwsIGxhc3RCb3JkZXJTZWdtZW50ID8gdnoueSA6IHliKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIGVkZ2UgPSB0aGlzLmNyZWF0ZUJvcmRlckVkZ2UoY2VsbC5zaXRlLCB2YSwgdmIpO1xuICAgICAgICAgICAgICAgICAgICAgICAgaUxlZnQrKztcbiAgICAgICAgICAgICAgICAgICAgICAgIGhhbGZlZGdlcy5zcGxpY2UoaUxlZnQsIDAsIHRoaXMuY3JlYXRlSGFsZmVkZ2UoZWRnZSwgY2VsbC5zaXRlLCBudWxsKSk7XG4gICAgICAgICAgICAgICAgICAgICAgICBuSGFsZmVkZ2VzKys7XG4gICAgICAgICAgICAgICAgICAgICAgICBpZiAoIGxhc3RCb3JkZXJTZWdtZW50ICkgeyBicmVhazsgfVxuICAgICAgICAgICAgICAgICAgICAgICAgdmEgPSB2YjtcbiAgICAgICAgICAgICAgICAgICAgICAgIC8vIGZhbGwgdGhyb3VnaFxuXG4gICAgICAgICAgICAgICAgICAgIC8vIHdhbGsgcmlnaHR3YXJkIGFsb25nIGJvdHRvbSBzaWRlXG4gICAgICAgICAgICAgICAgICAgIGNhc2UgdGhpcy5lcXVhbFdpdGhFcHNpbG9uKHZhLnkseWIpICYmIHRoaXMubGVzc1RoYW5XaXRoRXBzaWxvbih2YS54LHhyKTpcbiAgICAgICAgICAgICAgICAgICAgICAgIGxhc3RCb3JkZXJTZWdtZW50ID0gdGhpcy5lcXVhbFdpdGhFcHNpbG9uKHZ6LnkseWIpO1xuICAgICAgICAgICAgICAgICAgICAgICAgdmIgPSB0aGlzLmNyZWF0ZVZlcnRleChsYXN0Qm9yZGVyU2VnbWVudCA/IHZ6LnggOiB4ciwgeWIpO1xuICAgICAgICAgICAgICAgICAgICAgICAgZWRnZSA9IHRoaXMuY3JlYXRlQm9yZGVyRWRnZShjZWxsLnNpdGUsIHZhLCB2Yik7XG4gICAgICAgICAgICAgICAgICAgICAgICBpTGVmdCsrO1xuICAgICAgICAgICAgICAgICAgICAgICAgaGFsZmVkZ2VzLnNwbGljZShpTGVmdCwgMCwgdGhpcy5jcmVhdGVIYWxmZWRnZShlZGdlLCBjZWxsLnNpdGUsIG51bGwpKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIG5IYWxmZWRnZXMrKztcbiAgICAgICAgICAgICAgICAgICAgICAgIGlmICggbGFzdEJvcmRlclNlZ21lbnQgKSB7IGJyZWFrOyB9XG4gICAgICAgICAgICAgICAgICAgICAgICB2YSA9IHZiO1xuICAgICAgICAgICAgICAgICAgICAgICAgLy8gZmFsbCB0aHJvdWdoXG5cbiAgICAgICAgICAgICAgICAgICAgLy8gd2FsayB1cHdhcmQgYWxvbmcgcmlnaHQgc2lkZVxuICAgICAgICAgICAgICAgICAgICBjYXNlIHRoaXMuZXF1YWxXaXRoRXBzaWxvbih2YS54LHhyKSAmJiB0aGlzLmdyZWF0ZXJUaGFuV2l0aEVwc2lsb24odmEueSx5dCk6XG4gICAgICAgICAgICAgICAgICAgICAgICBsYXN0Qm9yZGVyU2VnbWVudCA9IHRoaXMuZXF1YWxXaXRoRXBzaWxvbih2ei54LHhyKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIHZiID0gdGhpcy5jcmVhdGVWZXJ0ZXgoeHIsIGxhc3RCb3JkZXJTZWdtZW50ID8gdnoueSA6IHl0KTtcbiAgICAgICAgICAgICAgICAgICAgICAgIGVkZ2UgPSB0aGlzLmNyZWF0ZUJvcmRlckVkZ2UoY2VsbC5zaXRlLCB2YSwgdmIpO1xuICAgICAgICAgICAgICAgICAgICAgICAgaUxlZnQrKztcbiAgICAgICAgICAgICAgICAgICAgICAgIGhhbGZlZGdlcy5zcGxpY2UoaUxlZnQsIDAsIHRoaXMuY3JlYXRlSGFsZmVkZ2UoZWRnZSwgY2VsbC5zaXRlLCBudWxsKSk7XG4gICAgICAgICAgICAgICAgICAgICAgICBuSGFsZmVkZ2VzKys7XG4gICAgICAgICAgICAgICAgICAgICAgICBpZiAoIGxhc3RCb3JkZXJTZWdtZW50ICkgeyBicmVhazsgfVxuICAgICAgICAgICAgICAgICAgICAgICAgdmEgPSB2YjtcbiAgICAgICAgICAgICAgICAgICAgICAgIC8vIGZhbGwgdGhyb3VnaFxuXG4gICAgICAgICAgICAgICAgICAgIC8vIHdhbGsgbGVmdHdhcmQgYWxvbmcgdG9wIHNpZGVcbiAgICAgICAgICAgICAgICAgICAgY2FzZSB0aGlzLmVxdWFsV2l0aEVwc2lsb24odmEueSx5dCkgJiYgdGhpcy5ncmVhdGVyVGhhbldpdGhFcHNpbG9uKHZhLngseGwpOlxuICAgICAgICAgICAgICAgICAgICAgICAgbGFzdEJvcmRlclNlZ21lbnQgPSB0aGlzLmVxdWFsV2l0aEVwc2lsb24odnoueSx5dCk7XG4gICAgICAgICAgICAgICAgICAgICAgICB2YiA9IHRoaXMuY3JlYXRlVmVydGV4KGxhc3RCb3JkZXJTZWdtZW50ID8gdnoueCA6IHhsLCB5dCk7XG4gICAgICAgICAgICAgICAgICAgICAgICBlZGdlID0gdGhpcy5jcmVhdGVCb3JkZXJFZGdlKGNlbGwuc2l0ZSwgdmEsIHZiKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIGlMZWZ0Kys7XG4gICAgICAgICAgICAgICAgICAgICAgICBoYWxmZWRnZXMuc3BsaWNlKGlMZWZ0LCAwLCB0aGlzLmNyZWF0ZUhhbGZlZGdlKGVkZ2UsIGNlbGwuc2l0ZSwgbnVsbCkpO1xuICAgICAgICAgICAgICAgICAgICAgICAgbkhhbGZlZGdlcysrO1xuICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCBsYXN0Qm9yZGVyU2VnbWVudCApIHsgYnJlYWs7IH1cbiAgICAgICAgICAgICAgICAgICAgICAgIHZhID0gdmI7XG4gICAgICAgICAgICAgICAgICAgICAgICAvLyBmYWxsIHRocm91Z2hcblxuICAgICAgICAgICAgICAgICAgICAgICAgLy8gd2FsayBkb3dud2FyZCBhbG9uZyBsZWZ0IHNpZGVcbiAgICAgICAgICAgICAgICAgICAgICAgIGxhc3RCb3JkZXJTZWdtZW50ID0gdGhpcy5lcXVhbFdpdGhFcHNpbG9uKHZ6LngseGwpO1xuICAgICAgICAgICAgICAgICAgICAgICAgdmIgPSB0aGlzLmNyZWF0ZVZlcnRleCh4bCwgbGFzdEJvcmRlclNlZ21lbnQgPyB2ei55IDogeWIpO1xuICAgICAgICAgICAgICAgICAgICAgICAgZWRnZSA9IHRoaXMuY3JlYXRlQm9yZGVyRWRnZShjZWxsLnNpdGUsIHZhLCB2Yik7XG4gICAgICAgICAgICAgICAgICAgICAgICBpTGVmdCsrO1xuICAgICAgICAgICAgICAgICAgICAgICAgaGFsZmVkZ2VzLnNwbGljZShpTGVmdCwgMCwgdGhpcy5jcmVhdGVIYWxmZWRnZShlZGdlLCBjZWxsLnNpdGUsIG51bGwpKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIG5IYWxmZWRnZXMrKztcbiAgICAgICAgICAgICAgICAgICAgICAgIGlmICggbGFzdEJvcmRlclNlZ21lbnQgKSB7IGJyZWFrOyB9XG4gICAgICAgICAgICAgICAgICAgICAgICB2YSA9IHZiO1xuICAgICAgICAgICAgICAgICAgICAgICAgLy8gZmFsbCB0aHJvdWdoXG5cbiAgICAgICAgICAgICAgICAgICAgICAgIC8vIHdhbGsgcmlnaHR3YXJkIGFsb25nIGJvdHRvbSBzaWRlXG4gICAgICAgICAgICAgICAgICAgICAgICBsYXN0Qm9yZGVyU2VnbWVudCA9IHRoaXMuZXF1YWxXaXRoRXBzaWxvbih2ei55LHliKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIHZiID0gdGhpcy5jcmVhdGVWZXJ0ZXgobGFzdEJvcmRlclNlZ21lbnQgPyB2ei54IDogeHIsIHliKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIGVkZ2UgPSB0aGlzLmNyZWF0ZUJvcmRlckVkZ2UoY2VsbC5zaXRlLCB2YSwgdmIpO1xuICAgICAgICAgICAgICAgICAgICAgICAgaUxlZnQrKztcbiAgICAgICAgICAgICAgICAgICAgICAgIGhhbGZlZGdlcy5zcGxpY2UoaUxlZnQsIDAsIHRoaXMuY3JlYXRlSGFsZmVkZ2UoZWRnZSwgY2VsbC5zaXRlLCBudWxsKSk7XG4gICAgICAgICAgICAgICAgICAgICAgICBuSGFsZmVkZ2VzKys7XG4gICAgICAgICAgICAgICAgICAgICAgICBpZiAoIGxhc3RCb3JkZXJTZWdtZW50ICkgeyBicmVhazsgfVxuICAgICAgICAgICAgICAgICAgICAgICAgdmEgPSB2YjtcbiAgICAgICAgICAgICAgICAgICAgICAgIC8vIGZhbGwgdGhyb3VnaFxuXG4gICAgICAgICAgICAgICAgICAgICAgICAvLyB3YWxrIHVwd2FyZCBhbG9uZyByaWdodCBzaWRlXG4gICAgICAgICAgICAgICAgICAgICAgICBsYXN0Qm9yZGVyU2VnbWVudCA9IHRoaXMuZXF1YWxXaXRoRXBzaWxvbih2ei54LHhyKTtcbiAgICAgICAgICAgICAgICAgICAgICAgIHZiID0gdGhpcy5jcmVhdGVWZXJ0ZXgoeHIsIGxhc3RCb3JkZXJTZWdtZW50ID8gdnoueSA6IHl0KTtcbiAgICAgICAgICAgICAgICAgICAgICAgIGVkZ2UgPSB0aGlzLmNyZWF0ZUJvcmRlckVkZ2UoY2VsbC5zaXRlLCB2YSwgdmIpO1xuICAgICAgICAgICAgICAgICAgICAgICAgaUxlZnQrKztcbiAgICAgICAgICAgICAgICAgICAgICAgIGhhbGZlZGdlcy5zcGxpY2UoaUxlZnQsIDAsIHRoaXMuY3JlYXRlSGFsZmVkZ2UoZWRnZSwgY2VsbC5zaXRlLCBudWxsKSk7XG4gICAgICAgICAgICAgICAgICAgICAgICBuSGFsZmVkZ2VzKys7XG4gICAgICAgICAgICAgICAgICAgICAgICBpZiAoIGxhc3RCb3JkZXJTZWdtZW50ICkgeyBicmVhazsgfVxuICAgICAgICAgICAgICAgICAgICAgICAgLy8gZmFsbCB0aHJvdWdoXG5cbiAgICAgICAgICAgICAgICAgICAgZGVmYXVsdDpcbiAgICAgICAgICAgICAgICAgICAgICAgIHRocm93IFwiVm9yb25vaS5jbG9zZUNlbGxzKCkgPiB0aGlzIG1ha2VzIG5vIHNlbnNlIVwiO1xuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgaUxlZnQrKztcbiAgICAgICAgICAgIH1cbiAgICAgICAgY2VsbC5jbG9zZU1lID0gZmFsc2U7XG4gICAgICAgIH1cbiAgICB9O1xuXG4vLyAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS1cbi8vIERlYnVnZ2luZyBoZWxwZXJcbi8qXG5Wb3Jvbm9pLnByb3RvdHlwZS5kdW1wQmVhY2hsaW5lID0gZnVuY3Rpb24oeSkge1xuICAgIGNvbnNvbGUubG9nKCdWb3Jvbm9pLmR1bXBCZWFjaGxpbmUoJWYpID4gQmVhY2hzZWN0aW9ucywgZnJvbSBsZWZ0IHRvIHJpZ2h0OicsIHkpO1xuICAgIGlmICggIXRoaXMuYmVhY2hsaW5lICkge1xuICAgICAgICBjb25zb2xlLmxvZygnICBOb25lJyk7XG4gICAgICAgIH1cbiAgICBlbHNlIHtcbiAgICAgICAgdmFyIGJzID0gdGhpcy5iZWFjaGxpbmUuZ2V0Rmlyc3QodGhpcy5iZWFjaGxpbmUucm9vdCk7XG4gICAgICAgIHdoaWxlICggYnMgKSB7XG4gICAgICAgICAgICBjb25zb2xlLmxvZygnICBzaXRlICVkOiB4bDogJWYsIHhyOiAlZicsIGJzLnNpdGUudm9yb25vaUlkLCB0aGlzLmxlZnRCcmVha1BvaW50KGJzLCB5KSwgdGhpcy5yaWdodEJyZWFrUG9pbnQoYnMsIHkpKTtcbiAgICAgICAgICAgIGJzID0gYnMucmJOZXh0O1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgfTtcbiovXG5cbi8vIC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLVxuLy8gSGVscGVyOiBRdWFudGl6ZSBzaXRlc1xuXG4vLyByaGlsbCAyMDEzLTEwLTEyOlxuLy8gVGhpcyBpcyB0byBzb2x2ZSBodHRwczovL2dpdGh1Yi5jb20vZ29yaGlsbC9KYXZhc2NyaXB0LVZvcm9ub2kvaXNzdWVzLzE1XG4vLyBTaW5jZSBub3QgYWxsIHVzZXJzIHdpbGwgZW5kIHVwIHVzaW5nIHRoZSBraW5kIG9mIGNvb3JkIHZhbHVlcyB3aGljaCB3b3VsZFxuLy8gY2F1c2UgdGhlIGlzc3VlIHRvIGFyaXNlLCBJIGNob3NlIHRvIGxldCB0aGUgdXNlciBkZWNpZGUgd2hldGhlciBvciBub3Rcbi8vIGhlIHNob3VsZCBzYW5pdGl6ZSBoaXMgY29vcmQgdmFsdWVzIHRocm91Z2ggdGhpcyBoZWxwZXIuIFRoaXMgd2F5LCBmb3Jcbi8vIHRob3NlIHVzZXJzIHdobyB1c2VzIGNvb3JkIHZhbHVlcyB3aGljaCBhcmUga25vd24gdG8gYmUgZmluZSwgbm8gb3ZlcmhlYWQgaXNcbi8vIGFkZGVkLlxuXG5Wb3Jvbm9pLnByb3RvdHlwZS5xdWFudGl6ZVNpdGVzID0gZnVuY3Rpb24oc2l0ZXMpIHtcbiAgICB2YXIgzrUgPSB0aGlzLs61LFxuICAgICAgICBuID0gc2l0ZXMubGVuZ3RoLFxuICAgICAgICBzaXRlO1xuICAgIHdoaWxlICggbi0tICkge1xuICAgICAgICBzaXRlID0gc2l0ZXNbbl07XG4gICAgICAgIHNpdGUueCA9IE1hdGguZmxvb3Ioc2l0ZS54IC8gzrUpICogzrU7XG4gICAgICAgIHNpdGUueSA9IE1hdGguZmxvb3Ioc2l0ZS55IC8gzrUpICogzrU7XG4gICAgICAgIH1cbiAgICB9O1xuXG4vLyAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS1cbi8vIEhlbHBlcjogUmVjeWNsZSBkaWFncmFtOiBhbGwgdmVydGV4LCBlZGdlIGFuZCBjZWxsIG9iamVjdHMgYXJlXG4vLyBcInN1cnJlbmRlcmVkXCIgdG8gdGhlIFZvcm9ub2kgb2JqZWN0IGZvciByZXVzZS5cbi8vIFRPRE86IHJoaWxsLXZvcm9ub2ktY29yZSB2MjogbW9yZSBwZXJmb3JtYW5jZSB0byBiZSBnYWluZWRcbi8vIHdoZW4gSSBjaGFuZ2UgdGhlIHNlbWFudGljIG9mIHdoYXQgaXMgcmV0dXJuZWQuXG5cblZvcm9ub2kucHJvdG90eXBlLnJlY3ljbGUgPSBmdW5jdGlvbihkaWFncmFtKSB7XG4gICAgaWYgKCBkaWFncmFtICkge1xuICAgICAgICBpZiAoIGRpYWdyYW0gaW5zdGFuY2VvZiB0aGlzLkRpYWdyYW0gKSB7XG4gICAgICAgICAgICB0aGlzLnRvUmVjeWNsZSA9IGRpYWdyYW07XG4gICAgICAgICAgICB9XG4gICAgICAgIGVsc2Uge1xuICAgICAgICAgICAgdGhyb3cgJ1Zvcm9ub2kucmVjeWNsZURpYWdyYW0oKSA+IE5lZWQgYSBEaWFncmFtIG9iamVjdC4nO1xuICAgICAgICAgICAgfVxuICAgICAgICB9XG4gICAgfTtcblxuLy8gLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tXG4vLyBUb3AtbGV2ZWwgRm9ydHVuZSBsb29wXG5cbi8vIHJoaWxsIDIwMTEtMDUtMTk6XG4vLyAgIFZvcm9ub2kgc2l0ZXMgYXJlIGtlcHQgY2xpZW50LXNpZGUgbm93LCB0byBhbGxvd1xuLy8gICB1c2VyIHRvIGZyZWVseSBtb2RpZnkgY29udGVudC4gQXQgY29tcHV0ZSB0aW1lLFxuLy8gICAqcmVmZXJlbmNlcyogdG8gc2l0ZXMgYXJlIGNvcGllZCBsb2NhbGx5LlxuXG5Wb3Jvbm9pLnByb3RvdHlwZS5jb21wdXRlID0gZnVuY3Rpb24oc2l0ZXMsIGJib3gpIHtcbiAgICAvLyB0byBtZWFzdXJlIGV4ZWN1dGlvbiB0aW1lXG4gICAgdmFyIHN0YXJ0VGltZSA9IG5ldyBEYXRlKCk7XG5cbiAgICAvLyBpbml0IGludGVybmFsIHN0YXRlXG4gICAgdGhpcy5yZXNldCgpO1xuXG4gICAgLy8gYW55IGRpYWdyYW0gZGF0YSBhdmFpbGFibGUgZm9yIHJlY3ljbGluZz9cbiAgICAvLyBJIGRvIHRoYXQgaGVyZSBzbyB0aGF0IHRoaXMgaXMgaW5jbHVkZWQgaW4gZXhlY3V0aW9uIHRpbWVcbiAgICBpZiAoIHRoaXMudG9SZWN5Y2xlICkge1xuICAgICAgICB0aGlzLnZlcnRleEp1bmt5YXJkID0gdGhpcy52ZXJ0ZXhKdW5reWFyZC5jb25jYXQodGhpcy50b1JlY3ljbGUudmVydGljZXMpO1xuICAgICAgICB0aGlzLmVkZ2VKdW5reWFyZCA9IHRoaXMuZWRnZUp1bmt5YXJkLmNvbmNhdCh0aGlzLnRvUmVjeWNsZS5lZGdlcyk7XG4gICAgICAgIHRoaXMuY2VsbEp1bmt5YXJkID0gdGhpcy5jZWxsSnVua3lhcmQuY29uY2F0KHRoaXMudG9SZWN5Y2xlLmNlbGxzKTtcbiAgICAgICAgdGhpcy50b1JlY3ljbGUgPSBudWxsO1xuICAgICAgICB9XG5cbiAgICAvLyBJbml0aWFsaXplIHNpdGUgZXZlbnQgcXVldWVcbiAgICB2YXIgc2l0ZUV2ZW50cyA9IHNpdGVzLnNsaWNlKDApO1xuICAgIHNpdGVFdmVudHMuc29ydChmdW5jdGlvbihhLGIpe1xuICAgICAgICB2YXIgciA9IGIueSAtIGEueTtcbiAgICAgICAgaWYgKHIpIHtyZXR1cm4gcjt9XG4gICAgICAgIHJldHVybiBiLnggLSBhLng7XG4gICAgICAgIH0pO1xuXG4gICAgLy8gcHJvY2VzcyBxdWV1ZVxuICAgIHZhciBzaXRlID0gc2l0ZUV2ZW50cy5wb3AoKSxcbiAgICAgICAgc2l0ZWlkID0gMCxcbiAgICAgICAgeHNpdGV4LCAvLyB0byBhdm9pZCBkdXBsaWNhdGUgc2l0ZXNcbiAgICAgICAgeHNpdGV5LFxuICAgICAgICBjZWxscyA9IHRoaXMuY2VsbHMsXG4gICAgICAgIGNpcmNsZTtcblxuICAgIC8vIG1haW4gbG9vcFxuICAgIGZvciAoOzspIHtcbiAgICAgICAgLy8gd2UgbmVlZCB0byBmaWd1cmUgd2hldGhlciB3ZSBoYW5kbGUgYSBzaXRlIG9yIGNpcmNsZSBldmVudFxuICAgICAgICAvLyBmb3IgdGhpcyB3ZSBmaW5kIG91dCBpZiB0aGVyZSBpcyBhIHNpdGUgZXZlbnQgYW5kIGl0IGlzXG4gICAgICAgIC8vICdlYXJsaWVyJyB0aGFuIHRoZSBjaXJjbGUgZXZlbnRcbiAgICAgICAgY2lyY2xlID0gdGhpcy5maXJzdENpcmNsZUV2ZW50O1xuXG4gICAgICAgIC8vIGFkZCBiZWFjaCBzZWN0aW9uXG4gICAgICAgIGlmIChzaXRlICYmICghY2lyY2xlIHx8IHNpdGUueSA8IGNpcmNsZS55IHx8IChzaXRlLnkgPT09IGNpcmNsZS55ICYmIHNpdGUueCA8IGNpcmNsZS54KSkpIHtcbiAgICAgICAgICAgIC8vIG9ubHkgaWYgc2l0ZSBpcyBub3QgYSBkdXBsaWNhdGVcbiAgICAgICAgICAgIGlmIChzaXRlLnggIT09IHhzaXRleCB8fCBzaXRlLnkgIT09IHhzaXRleSkge1xuICAgICAgICAgICAgICAgIC8vIGZpcnN0IGNyZWF0ZSBjZWxsIGZvciBuZXcgc2l0ZVxuICAgICAgICAgICAgICAgIGNlbGxzW3NpdGVpZF0gPSB0aGlzLmNyZWF0ZUNlbGwoc2l0ZSk7XG4gICAgICAgICAgICAgICAgc2l0ZS52b3Jvbm9pSWQgPSBzaXRlaWQrKztcbiAgICAgICAgICAgICAgICAvLyB0aGVuIGNyZWF0ZSBhIGJlYWNoc2VjdGlvbiBmb3IgdGhhdCBzaXRlXG4gICAgICAgICAgICAgICAgdGhpcy5hZGRCZWFjaHNlY3Rpb24oc2l0ZSk7XG4gICAgICAgICAgICAgICAgLy8gcmVtZW1iZXIgbGFzdCBzaXRlIGNvb3JkcyB0byBkZXRlY3QgZHVwbGljYXRlXG4gICAgICAgICAgICAgICAgeHNpdGV5ID0gc2l0ZS55O1xuICAgICAgICAgICAgICAgIHhzaXRleCA9IHNpdGUueDtcbiAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICBzaXRlID0gc2l0ZUV2ZW50cy5wb3AoKTtcbiAgICAgICAgICAgIH1cblxuICAgICAgICAvLyByZW1vdmUgYmVhY2ggc2VjdGlvblxuICAgICAgICBlbHNlIGlmIChjaXJjbGUpIHtcbiAgICAgICAgICAgIHRoaXMucmVtb3ZlQmVhY2hzZWN0aW9uKGNpcmNsZS5hcmMpO1xuICAgICAgICAgICAgfVxuXG4gICAgICAgIC8vIGFsbCBkb25lLCBxdWl0XG4gICAgICAgIGVsc2Uge1xuICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICB9XG4gICAgICAgIH1cblxuICAgIC8vIHdyYXBwaW5nLXVwOlxuICAgIC8vICAgY29ubmVjdCBkYW5nbGluZyBlZGdlcyB0byBib3VuZGluZyBib3hcbiAgICAvLyAgIGN1dCBlZGdlcyBhcyBwZXIgYm91bmRpbmcgYm94XG4gICAgLy8gICBkaXNjYXJkIGVkZ2VzIGNvbXBsZXRlbHkgb3V0c2lkZSBib3VuZGluZyBib3hcbiAgICAvLyAgIGRpc2NhcmQgZWRnZXMgd2hpY2ggYXJlIHBvaW50LWxpa2VcbiAgICB0aGlzLmNsaXBFZGdlcyhiYm94KTtcblxuICAgIC8vICAgYWRkIG1pc3NpbmcgZWRnZXMgaW4gb3JkZXIgdG8gY2xvc2Ugb3BlbmVkIGNlbGxzXG4gICAgdGhpcy5jbG9zZUNlbGxzKGJib3gpO1xuXG4gICAgLy8gdG8gbWVhc3VyZSBleGVjdXRpb24gdGltZVxuICAgIHZhciBzdG9wVGltZSA9IG5ldyBEYXRlKCk7XG5cbiAgICAvLyBwcmVwYXJlIHJldHVybiB2YWx1ZXNcbiAgICB2YXIgZGlhZ3JhbSA9IG5ldyB0aGlzLkRpYWdyYW0oKTtcbiAgICBkaWFncmFtLmNlbGxzID0gdGhpcy5jZWxscztcbiAgICBkaWFncmFtLmVkZ2VzID0gdGhpcy5lZGdlcztcbiAgICBkaWFncmFtLnZlcnRpY2VzID0gdGhpcy52ZXJ0aWNlcztcbiAgICBkaWFncmFtLmV4ZWNUaW1lID0gc3RvcFRpbWUuZ2V0VGltZSgpLXN0YXJ0VGltZS5nZXRUaW1lKCk7XG5cbiAgICAvLyBjbGVhbiB1cFxuICAgIHRoaXMucmVzZXQoKTtcblxuICAgIHJldHVybiBkaWFncmFtO1xuICAgIH07XG5cbm1vZHVsZS5leHBvcnRzID0gVm9yb25vaTtcbiJdfQ==
