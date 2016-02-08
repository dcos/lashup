
// Blatantly stolen from StackOverflow:
// http://stackoverflow.com/questions/10406930/how-to-construct-a-websocket-uri-relative-to-the-page-uri
function createWebSocket(path) {
    var protocolPrefix = (window.location.protocol === 'https:') ? 'wss:' : 'ws:';
    return new WebSocket(protocolPrefix + '//' + location.host + path);
}
var gm_nodes = {};
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
    var message = JSON.parse(evt.data);
    if (message["message_type"] == "initial_state") {
        process_initial_state(message);
    }
    console.log(evt);
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

function process_initial_state(message) {
    for (var nn in message["nodes"]) {
        gm_nodes[nn] = message["nodes"][nn];
        cy.add({
            group: "nodes",
            data: { id: nn },
            name: nn
        });
        //nodes.push(gm_nodes[nn]);
        //console.log(nn);
    }
    createLinks();
    defaultLayout();
}
function createLinks() {
    edges = [];
    for (var nn in gm_nodes) {
        var active_view = gm_nodes[nn]["active_view"];
        active_view.forEach(function(target) {
            a = [nn, target];
            a.sort();
            id = a.join('_')

            edges.push({ group: "edges", data: { id: id, source: nn, target: target } })
        });
    }
    cy.add(edges);
}
var cy;
var layout = null;

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
                        'background-color': '#ccc',
                        'label': 'data(id)',
                        'font-size': '8px',
                        'text-valign': 'center',
                        'text-halign': 'center'
                    }
                },

                {
                    selector: 'edge',
                    style: {
                        'width': 3,
                        'line-color': '#ccc',
                        'curve-style': 'unbundled-bezier'
                    }
                }
            ]
        }
    );
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

}

function defaultLayout() {
    if (layout) { layout.stop(); };
    layout = cy.makeLayout({
        name: 'circle',
        nodeSpacing: 5,
        edgeLengthVal: 45,
        animate: true,
        randomize: false,
        maxSimulationTime: 1500,
        animationDuration: 1500
    });
    layout.run();
}