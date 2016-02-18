var colorScale = d3.scale.linear().domain([0, 500, 1001]).range(['green', 'yellow', 'red']);

// Blatantly stolen from StackOverflow:
// http://stackoverflow.com/questions/10406930/how-to-construct-a-websocket-uri-relative-to-the-page-uri
function createWebSocket(path) {
    var protocolPrefix = (window.location.protocol === 'https:') ? 'wss:' : 'ws:';
    return new WebSocket(protocolPrefix + '//' + location.host + path);
}
var websocket;
function lashup_init() {
    // Another stackoverflow: http://stackoverflow.com/questions/14140414/websocket-interrupted-while-page-is-loading-on-firefox-for-socket-io
    $(window).on('beforeunload', function(){
        websocket.close();
    });

    websocket = createWebSocket("/websocket");
    websocket.onclose = function(evt) { onClose(evt) };
    websocket.onmessage = function(evt) { onMessage(evt) };
    websocket.onerror = function(evt) { onError(evt) };
    websocket.onopen = function(evt) { onOpen(evt) };
    setupGraph();
}
function onClose(evt) {
    console.log(evt);
}
function onMessage(evt) {
    console.log(evt);
    var message = JSON.parse(evt.data);
    var mt = message["message_type"];
    if (mt == "initial_state") {
        process_initial_state(message);
    } else if (mt == "node_update") {
        node_update(message);
    } else if (mt == "latency_update") {
        latency_update(message);
    }
}
function onError(evt) {
   console.log(evt);
}
function onOpen(evt) {
    sendMessage({"type": "subscribe"})
}
function sendMessage(msg) {
    websocket.send(JSON.stringify(msg));
}

function node_update(message) {
    maybeAddOrUpdateNode(message.node_update);
}
function process_initial_state(message) {
    for (var nn in message["nodes"]) {
        addNode(message["nodes"][nn]);
    }
    for (var nn in message["nodes"]) {
        updateNode(message["nodes"][nn]);
    }
}

function maybeAddOrUpdateNode(node) {
    if (cy.getElementById(node.name).isNode())
    {
        updateNode(node);
    } else {
        addNode(node);
        updateNode(node);
    }
}
function updateNode(node) {
    // Basically here to ensure the edges are right
    element = cy.getElementById(node.name);
    oldActiveView = [];
    if (element.data('active_view')) {
        oldActiveView = element.data('active_view');
    }
    element.data('active_view', node['active_view']);
    element.data('opaque', node['opaque']);
    if(node.active_view.forEach && oldActiveView.forEach) {
        node.active_view.forEach(maybeDoBidiLink(element));
        oldActiveView.forEach(maybeDoBidiLink(element));
    }
    defaultLayout();
}
function maybeDoBidiLink(localNodeElement) {
    return function(otherNode) {
        // Checks that the other node has me in their sights
        otherNodeElement = cy.getElementById(otherNode);
        if (!otherNodeElement) { return; }
        otherNodeActiveView = otherNodeElement.data('active_view');
        if (!otherNodeActiveView) { return }
        myActiveView = localNodeElement.data('active_view');
        myActiveViewSet = new Set(myActiveView);
        otherNodeActiveViewSet = new Set(otherNodeActiveView);
        if (myActiveViewSet.has(otherNode) && otherNodeActiveViewSet.has(localNodeElement.id())) {
            ensureEdge(localNodeElement.id(), otherNode);
            ensureEdge(otherNode, localNodeElement.id());
        } else {
            ensureEdgeDeleted(localNodeElement.id(), otherNode);
            ensureEdgeDeleted(otherNode, localNodeElement.id());
        }
    }
}

function addNode(node) {
    Data = {
        group: "nodes",
        data: {
            id: node.name,
            'active_view': node.active_view,
            'opaque': node.opaque
        },
    }
    return cy.add(Data)
}
function ensureEdge(node1, node2) {
    id = edgeId(node1, node2);
    if (!cy.getElementById(id).isEdge()) {
        cy.add(nodesToEdge(node1, node2));
    }
}

function ensureEdgeDeleted(node1, node2) {
    id = edgeId(node1, node2);
    if (cy.getElementById(id).isEdge()) {
        cy.remove(cy.getElementById(id));
    }
}

function edgeId(source, dest)  {
    a = ['edge', source, dest];
    id = a.join('_');
    return id;
}
function nodesToEdge(name1, name2) {
    id = edgeId(name1, name2);
    base =
    {
        group: "edges",
        data: {
            'latencyMaybe': '#ccc',
            id: id,
            source: name1,
            target: name2
        }
    };
    return base;
}

function latency_update(message) {
    origin = message['origin']
    to_nodes = message['to_nodes']
    for (var to_node in to_nodes) {
        var id = edgeId(origin, to_node);
        if (cy.getElementById(id) && cy.getElementById(id).isEdge())
        {
            color = colorScale(to_nodes[to_node]);
            cy.getElementById(id).data('latencyMaybe', color);
        }
    }
}
var cy;
var layout = null;

function getBorderColor( ele ) {
    if (ele.data('opaque').source) {
        return 'black';
    } else {
        return 'gray';
    }
}
function getBackgroundColor(ele) {
    if (ele.data('opaque').reachable) {
        return 'green';
    } else {
        return 'red';
    }
}
function setupGraph() {
    cy = cytoscape(
        {
            container: document.getElementById('lashup'), // container to render in
            style: [
                {
                    selector: 'node',
                    style: {
                        'height': 20,
                        'width': 120,
                        'background-color': getBackgroundColor,
                        'label': 'data(id)',
                        'font-size': '8px',
                        'text-valign': 'center',
                        'text-halign': 'center',
                        'border-width': 5,
                        'border-color': getBorderColor
                    }
                },

                {
                    selector: 'edge',
                    style: {
                        'width': 5,
                        'line-color': 'data(latencyMaybe)',
                        'curve-style': 'unbundled-bezier'
                    }
                }
            ]
        }
    );
    /*
    cy.on('grab', function(event){
        if (event.cyTarget.isNode()) {
            if (layout) { layout.stop(); };
            layout = cy.makeLayout({
                roots: [event.cyTarget.id()],
                name: 'breadthfirst',
                nodeSpacing: 5,
                edgeLengthVal: 45,
                animate: true,
                randomize: false,
                maxSimulationTime: 1500,
                animationDuration: 1500
            });
            layout.run()
        }
    });
    cy.on('tap', function(event){
        // cyTarget holds a reference to the originator
        // of the event (core or element)
        var evtTarget = event.cyTarget;

        if( evtTarget === cy ){
            defaultLayout();
        }
    });
    */

}

function defaultLayout() {
    if (layout) { layout.stop(); };
    layout = cy.makeLayout({
        name: 'concentric',
        nodeSpacing: 5,
        edgeLengthVal: 45,
        animate: true,
        randomize: false,
        maxSimulationTime: 1500,
        animationDuration: 1500,
        fit: false,
        concentric: function(node){ // returns numeric value for each node, placing higher nodes in levels towards the centre
            if (node.data('opaque').reachable) {
                return node.degree() + 1;
            } else {
                return 0;
            }
        },
        levelWidth: function(nodes){ // the variation of concentric values in each level
            return nodes.maxDegree() + 1;
        },
    });
    layout.run();
};