/*!
Copyright (c) The Cytoscape Consortium

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the “Software”), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

;(function(){ 'use strict';

  // registers the extension on a cytoscape lib ref
  var register = function( cytoscape, arbor ){
    if( !cytoscape || !arbor ){ return; } // can't register if cytoscape unspecified

    var defaults = {
      animate: true, // whether to show the layout as it's running
      maxSimulationTime: 4000, // max length in ms to run the layout
      fit: true, // on every layout reposition of nodes, fit the viewport
      padding: 30, // padding around the simulation
      boundingBox: undefined, // constrain layout bounds; { x1, y1, x2, y2 } or { x1, y1, w, h }
      ungrabifyWhileSimulating: false, // so you can't drag nodes during layout
      randomize: false, // uses random initial node positions on true

      // callbacks on layout events
      ready: undefined, // callback on layoutready
      stop: undefined, // callback on layoutstop

      // forces used by arbor (use arbor default on undefined)
      repulsion: undefined,
      stiffness: undefined,
      friction: undefined,
      gravity: true,
      fps: undefined,
      precision: undefined,

      // static numbers or functions that dynamically return what these
      // values should be for each element
      // e.g. nodeMass: function(n){ return n.data('weight') }
      nodeMass: undefined,
      edgeLength: undefined,

      stepSize: 0.1, // smoothing of arbor bounding box

      // function that returns true if the system is stable to indicate
      // that the layout can be stopped
      stableEnergy: function( energy ){
        var e = energy;
        return (e.max <= 0.5) || (e.mean <= 0.3);
      },

      // infinite layout options
      infinite: false // overrides all other options for a forces-all-the-time mode
    };

    function ArborLayout(options){
      var opts = this.options = {};
      for( var i in defaults ){ opts[i] = defaults[i]; }
      for( var i in options ){ opts[i] = options[i]; }
    }

    ArborLayout.prototype.run = function(){
      var layout = this;
      var options = this.options;
      var cy = options.cy;
      var eles = options.eles;
      var nodes = eles.nodes().not(':parent');
      var edges = eles.edges();
      var simUpdatingPos = false;

      var bb = options.boundingBox || { x1: 0, y1: 0, w: cy.width(), h: cy.height() };
      if( bb.x2 === undefined ){ bb.x2 = bb.x1 + bb.w; }
      if( bb.w === undefined ){ bb.w = bb.x2 - bb.x1; }
      if( bb.y2 === undefined ){ bb.y2 = bb.y1 + bb.h; }
      if( bb.h === undefined ){ bb.h = bb.y2 - bb.y1; }

      layout.trigger({ type: 'layoutstart', layout: layout });

      // backward compatibility for old animation option
      if( options.liveUpdate !== undefined ){
        options.animate = options.liveUpdate;
      }

      // arbor doesn't work with just 1 node
      if( eles.nodes().size() <= 1 ){
        if( options.fit ){
          cy.reset();
        }

        eles.nodes().position({
          x: Math.round( (bb.x1 + bb.x2)/2 ),
          y: Math.round( (bb.y1 + bb.y2)/2 )
        });

        layout.one('layoutready', options.ready);
        layout.trigger({ type: 'layoutready', layout: layout });

        layout.one('layoutstop', options.stop);
        layout.trigger({ type: 'layoutstop', layout: layout });

        return;
      }

      var sys = layout.system = arbor.ParticleSystem();

      sys.parameters({
        repulsion: options.repulsion,
        stiffness: options.stiffness,
        friction: options.friction,
        gravity: options.gravity,
        fps: options.fps,
        dt: options.dt,
        precision: options.precision
      });

      if( options.animate && options.fit ){
        cy.fit( bb, options.padding );
      }

      var doneTime = 250;
      var doneTimeout;

      var ready = false;

      var lastDraw = +new Date();
      var sysRenderer = {
        init: function(system){
        },
        redraw: function(){
          var energy = sys.energy();

          // if we're stable (according to the client), we're done
          if( !options.infinite && options.stableEnergy != null && energy != null && energy.n > 0 && options.stableEnergy(energy) ){
            layout.stop();
            return;
          }

          if( !options.infinite && doneTime != Infinity ){
            clearTimeout(doneTimeout);
            doneTimeout = setTimeout(doneHandler, doneTime);
          }

          var movedNodes = cy.collection();

          sys.eachNode(function(n, point){
            var data = n.data;
            var node = data.element;

            if( node == null ){
              return;
            }

            if( !node.locked() && !node.grabbed() ){
              node.silentPosition({
                x: bb.x1 + point.x,
                y: bb.y1 + point.y
              });

              movedNodes.merge( node );
            }
          });


          if( options.animate && movedNodes.length > 0 ){
            simUpdatingPos = true;

            movedNodes.rtrigger('position');

            if( options.fit ){
              cy.fit( options.padding );
            }

            lastDraw = +new Date();
            simUpdatingPos = false;
          }


          if( !ready ){
            ready = true;
            layout.one('layoutready', options.ready);
            layout.trigger({ type: 'layoutready', layout: layout });
          }
        }

      };
      sys.renderer = sysRenderer;
      sys.screenSize( bb.w, bb.h );
      sys.screenPadding( options.padding, options.padding, options.padding, options.padding );
      sys.screenStep( options.stepSize );

      function calculateValueForElement(element, value){
        if( value == null ){
          return undefined;
        } else if( typeof value == typeof function(){} ){
          return value.apply(element, [element.data(), {
            nodes: nodes.length,
            edges: edges.length,
            element: element
          }]);
        } else {
          return value;
        }
      }

      var grabHandler;
      nodes.on('grab free position', grabHandler = function(e){
        if( simUpdatingPos ){ return; }

        var pos = this.position();
        var apos = sys.fromScreen( pos );
        if( !apos ){ return; }

        var p = arbor.Point(apos.x, apos.y);
        var padding = options.padding;

        if(
          bb.x1 + padding <= pos.x && pos.x <= bb.x2 - padding &&
          bb.y1 + padding <= pos.y && pos.y <= bb.y2 - padding
        ){
          this.scratch().arbor.p = p;
        }

        switch( e.type ){
        case 'grab':
          this.scratch().arbor.fixed = true;
          break;
        case 'free':
          this.scratch().arbor.fixed = false;
          //this.scratch().arbor.tempMass = 1000;
          break;
        }
      });

      var lockHandler;
      nodes.on('lock unlock', lockHandler = function(e){
        node.scratch().arbor.fixed = node.locked();
      });

      var resizeHandler;
      cy.on('resize', resizeHandler = function(){
        if( options.boundingBox == null && layout.system != null ){
          var w = cy.width();
          var h = cy.height();

          sys.screenSize( w, h );
        }
      });

      function addNode( node ){
        if( node.isFullAutoParent() ){ return; } // they don't exist in the sim

        var id = node.id();
        var mass = calculateValueForElement(node, options.nodeMass);
        var locked = node.locked();
        var nPos = node.position();

        if( options.randomize ){
          nPos = {
            x: Math.round( bb.x1 + (bb.x2 - bb.x1) * Math.random() ),
            y: Math.round( bb.y1 + (bb.y2 - bb.y1) * Math.random() )
          };
        }

        var pos = sys.fromScreen({
          x: nPos.x,
          y: nPos.y
        });

        node.scratch().arbor = sys.addNode(id, {
          element: node,
          mass: mass,
          fixed: locked,
          x: locked && pos ? pos.x : undefined,
          y: locked && pos ? pos.y : undefined
        });
      }

      function addEdge( edge ){
        var src = edge.source().id();
        var tgt = edge.target().id();
        var length = calculateValueForElement(edge, options.edgeLength);

        edge.scratch().arbor = sys.addEdge(src, tgt, {
          length: length
        });
      }

      nodes.each(function(i, node){
        addNode( node );
      });

      edges.each(function(i, edge){
        addEdge( edge );
      });

      var grabbableNodes = nodes.filter(":grabbable");
      // disable grabbing if so set
      if( options.ungrabifyWhileSimulating ){
        grabbableNodes.ungrabify();
      }

      var doneHandler = layout.doneHandler = function(){
        layout.doneHandler = null;

        if( !options.animate ){
          if( options.fit ){
            cy.reset();
          }

          nodes.rtrigger('position');
        }

        // unbind handlers
        nodes.off('grab free position', grabHandler);
        nodes.off('lock unlock', lockHandler);
        cy.off('resize', resizeHandler);

        // enable back grabbing if so set
        if( options.ungrabifyWhileSimulating ){
          grabbableNodes.grabify();
        }

        layout.one('layoutstop', options.stop);
        layout.trigger({ type: 'layoutstop', layout: layout });
      };

      sys.start();
      if( !options.infinite && options.maxSimulationTime != null && options.maxSimulationTime > 0 && options.maxSimulationTime !== Infinity ){
        setTimeout(function(){
          layout.stop();
        }, options.maxSimulationTime);
      }

      return this; // chaining
    };

    ArborLayout.prototype.stop = function(){
      if( this.system != null ){
        this.system.stop();
      }

      if( this.doneHandler ){
        this.doneHandler();
      }

      return this; // chaining
    };

    cytoscape('layout', 'arbor', ArborLayout);

  };

  if( typeof module !== 'undefined' && module.exports ){ // expose as a commonjs module
    module.exports = register;
  }

  if( typeof define !== 'undefined' && define.amd ){ // expose as an amd/requirejs module
    define('cytoscape-arbor', function(){
      return register;
    });
  }

  if( typeof cytoscape !== 'undefined' ){ // expose to global cytoscape (i.e. window.cytoscape)
    register( cytoscape, arbor );
  }

})();
