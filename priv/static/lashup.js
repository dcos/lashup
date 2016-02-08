
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
        nodes.push(gm_nodes[nn]);
        //console.log(nn);
    }
    createLinks();
    restart();
}
function createLinks() {
    for (var nn in gm_nodes) {
        var active_view = gm_nodes[nn]["active_view"];
        active_view.forEach(function(target) {
            links.push({"source": gm_nodes[nn], "target": gm_nodes[target]})
        });
    }
}

var force;
var nodes = [
];
var links = [
    //{"source":nodes[0], "target":nodes[1]}
];
var node;
var link;
var svg;
var color = d3.scale.category20();


function setupGraph() {
    var width = 1280, height = 960;

    svg = d3.select("body").append("svg")
        .attr("width", width)
        .attr("height", height);

    force = d3.layout.force()
        .size([width, height])
        .nodes(nodes)
        .links(links);

    force.linkDistance(width/3);

    force.linkStrength(0.1);

    force.gravity(0.05);

    force.charge(
        function(node) {
            return -300;
        }
    )
    force.on("tick", tick);
    restart();
}

function magic() {
    link = svg.selectAll(".link")
        .data(links);
    linkenter = link
        .enter()
        .append("line")
        .attr("class", "link");

    linkexit = link
        .exit();
    linkexit.remove();

    linkenter
        .style("stroke-width", function(d) { return 5; });

    node = svg.selectAll(".node")
        .data(nodes);

    nodeexit = node.exit();
    nodeexit.remove();

    nodeenter = node
        .enter()
        .append("g")
        .attr("class", "node");

    nodeenter.call(force.drag);


    nodeenter
        .append("ellipse")
        .attr("rx", 75)
        .attr("ry", 20)
      //  .attr("fill", function(d) { return color(d.name); })
        .attr("fill", "white")
        .attr("fill-opacity", 1.00)
        .attr("stroke", "black");

    nodeenter
        .append("text")
        .attr("text-anchor", "middle")
        .text(function(d) { return d.name });
}

function tick() {
    link.attr("x1", function(d) { return d.source.x; })
        .attr("y1", function(d) { return d.source.y; })
        .attr("x2", function(d) { return d.target.x; })
        .attr("y2", function(d) { return d.target.y; });

    node.attr("transform", function(d) { return "translate(" + d.x + "," + d.y + ")"; });

}


function restart() {
    magic();
    force.start();
}