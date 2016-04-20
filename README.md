# Lashup
[![Circle CI](https://circleci.com/gh/dcos/lashup.svg?style=svg&circle-token=e109b76cf8a017424100d9269640771210d7efe3)](https://circleci.com/gh/dcos/lashup)
[![Velocity](http://velocity.mesosphere.com/service/velocity/buildStatus/icon?job=dcos-networking-lashup-master/)](http://velocity.mesosphere.com/service/velocity/job/dcos-networking-lashup-master/)
## Summary 
Lashup is a building block for a distributed control plane. It acts as a failure detector, a distributed fully-replicated CRDT store, and a multicast system. It isn't meant to be used by itself, but rather in conjunction with other components. In this it has several components:
 
### Overlay Builder
The core of lashup is the overlay builder. This is a strongly connected, sparse graph of TCP connections used for communication. The primary reason to do this is scalability. If every node had to healthcheck every other node, or maintain connections to every other node, we would quickly see scalability problems. In the code, these are the files `lashup_hyparview`, as the implementation is heavily based off of [Hyparview](http://asc.di.fct.unl.pt/~jleitao/pdf/dsn07-leitao.pdf), but with a few changes:
1. We use randomized timers instead of rounds
2. We introduced a throttling mechanism. We found that it took longer for the overlay to become stable if we didn't throttle joins.
3. We store the members to disk and occassionally healthcheck them

### Routing & Failure Detection
Atop the overlay, we have a routing and failure detection layer. Each node in the Lashup network distributes its adjacencies to every other node in the system, and these are stored in memory. We found that at 1000 nodes, the typical size of this database is under 50 mb. The *fan-out* is set to **6** based on some static tunables in overlay layer. Whenever there are changes to a given node's adjacency table, it gossips this throughout the network. 

The nodes also healthcheck one another. The healthcheck algorithm is an adaptive algorithm. We set the initial expected round trip time to 1 second. We then proceed to ping every one of our adjacencies every second. The historical round trip times are cached, and we use a logrithmic scale to determine how long future round trips should take. If a node fails to respond, we immediately disconnect it, and propagate that information through the gossip. At this point, all of the nodes that are also connected to that node proceed to healthcheck it. This results in typical sub-second failure detection. If the overlay is unstable, the ping intervals are naturally elevated, and therefore inhibit rejection of nodes from the overlay.

Once we have this adjacency table, we then run a depth first search on it to build a minimum spanning tree. This minimum spanning tree then becomes a mechanism to build sender-rooted multicast messages.  

### Distributed Database
Lastly, and most interestingly, Lashup is a distributed database. Lashup acts as a CRDT store. It is built on top of Basho's [riak_dt](https://github.com/basho/riak_dt). Every key is replicated to every node. Rather than performing read-modify writes, the CRDT store offers operations. Specifically, you can operate on counters, maps, sets, flags, or registers. You can also compose these datastructures to build a complex model. Given that Lashup isn't meant to work with a high key count, due to the naivette of its anti-entropy algorithm, it is preferential to build a map. 

The data is also persisted to disk via Mnesia. Mnesia was chosen due to its reliability, and testing in production, as well as the fact that it requires no dependencies outside of Erlang itself.

## Background

Project Lashup is an underlying infrastructure system to enable Project Minuteman. The purpose of Project Lashup is to enable Project Minuteman to determine the list of available backends to fulfill a connection request. The purpose of Project Lashup in the context of Peacekeeper is to disseminate the list of IP, and Port endpoints. The system has to have strong availability performance properties, and availability properties. It is also known as the "Event Fabric".
Lashup will run on every agent. Most of the information needed can be derived from an Agent's TaskInfo, and TaskStatus.  Therefore, the initial version of Lashup's purpose is to advertise an up to date version of an Agent's Tasks. In addition to this, it must replicate this state to all other nodes running Lashup. This can be modeled as a key/value system, where every agent has its own namespace, that it, and only it can write to, but other agents can read from. The estimate of the information needed in TaskInfo is likely to be under a kilobyte, and the TaskStatus is likely to be under 512 kilobytes. Efficiencies can be taken in order to only advertise mutations, such as the work from the [Delta-CRDT paper](http://arxiv.org/abs/1410.2803). 
Since this information is used to make routing decisions, it must be disseminated in a timely manner. Lashup should provide strong guarantees about timely convergence not only under partial failure, but typical operating conditions. Although it is not a strong requirement, Lashup should also provide a mechanism to determine whether a replica (agent) has entirely failed to avoid sending requests to it. It is likely that a different mechanism will have to be used for state dissemination versus liveness checking. 

### Failure Detector
Prior to having a gossip protocol, Project Lashup needs to provide a failure detector for Project Minuteman. The purpose of the failure detector is to allow slower dissemination of data - whether it be through a cache, a broker, or something else. The reason for this is that agents can advertise their state independently of their health. Doing this allows us to handle stale data better because we can retire the advertised VIPs of agents more quickly than a period a epidemic-gossip system would take to disseminate said data.

We need a failure detector that's quick to converge (less than 1.5 seconds for disseminating a member failure to 90% of the cluster), and a failure detector that can detect asymmetric network partitions. For example, assume we have master M1, M2, and M3, and agents A1, A2, A3, A4, and A5. We want to be able to detect the case where A[1-5] can communicate to M[1-3], but A[1-2] cannot communicate with A[3-5]. Ideally, we also want the failure detector to enable instigating healthchecks based on Minuteman connections. We do not want to mark any member of the set A[1-5] as failed if A[1-5] cannot communicate with M[1-3]. Such []network partitions happen often](https://queue.acm.org/detail.cfm?id=2655736). Many of these are caused by misconfiguration. 

## Uses
### Detecting failure
The first obvious use case for Lashup is to detect the failure of agents in the system. If we're sending traffic to a node via a load balancing mechanism, we can react to node failure faster than Mesos (10M), or other mechanisms can detect failure by using techniques like gossip, and indirect healthchecks. Alternatively, DCOS takes advantage of Mesos, which can have slow periods for detecting faults. 

### Publishing VIPs
The second use case for Lashup is to publish VIPs for Minuteman. These VIPs will be derived by reading the local agent's state.json, and deriving the VIPs from the state.json. The result of this is a map of sets. These maps can be simply merged across agents, with the merge operation for a set being a simple merge. 
Powering Novel Load Balancing Algorithms
Once there is a reliable failure detector, and a mechanism to disseminate specific data, it can be extended. Although we can trivially implement local least connections, and global random, these load balancing algorithms aren't often always the ideal mechanism for interactive web services. One such algorithm is Microsoft's Join-Idle-Queue: http://research.microsoft.com/apps/pubs/default.aspx?id=153348. It effectively requires a mechanism to expose queue depth to routers. Other algorithms, such as performance-based routing require very small amounts of metadata to be exposed, with very short update periods. 

### Security
Security is being implemented by Project Peacekeeper. Project Peacekeeper intercepts the first packet of every connection. The complexity is determining the destination. In order to determine the destination, the task list must be queried to find the task with matching NetworkInfo, and allocated ports. This information is difficult to cache, as it will have high churn, and overly aggressive caching can potentially lead to a security compromise. 
In such a distributed filtering system, there is also a requirement to distribute the filtering rules to all of the nodes in a timely fashion, otherwise users can be left without connectivity, or users may have too much connectivity.

## Usage
Integrating Lashup into your own project is easy! You must set the configuration, `{mnesia, dir}` for the KV store to persist its data, and the `{lashup, work_dir}` to persist the Lamport clock used in the gossip algorithm. You must also set the contact_nodes via the configuration parameter `{lashup, contact_nodes}`. These nodes are used to bootstrap the overlay. They can fail without many downsides, but if all of them are down, new nodes cannot join the overlay.

### Membership
You can get the global membership by using `lashup_gm:gm()`. If you're interested in finding out about changes the the global membership, the gen_event `lashup_gm_events` can be useful to subscribe to. If you're interested in finding out reachability information, you can call `lashup_gm_route:get_tree(Origin)` to get the DFS tree from that Origin. It returns a map, where the key is the destination node name, and the value is either the distance from the given origin, or `infinity`, if the node is unreachable. 

### Key Value Store
The key value store exposes a traditional API, and a subscribe API. You can request ops to the key value store by simply running `lashup_kv:request_op(Key, Op)`, where the Op is a riak_dt operation. A few usages can be found in the [test suite](https://github.com/dcos/lashup/blob/master/test/lashup_kv_SUITE.erl). 
#### Subscribe API
The subscription API allows you to susbcribe to key value changes that match a specific pattern. We use standard ets match specs for this purpose. The matchspec must return `true`. For example: 
`ets:fun2ms(fun({[node_metadata|_]}) -> true end)`. The matchspec must be a 1-tuple, where the only member of the tuple is the pattern of the key. 

Then you can simply call `lashup_kv_events_helper:start_link(ets:fun2ms(fun({[node_metadata|_]}) -> true end))`. This will dump all existing keys with that pattern, and send you future keys matching that pattern. In addition, we will deduplicate updates and only send you new updates.

### Multicast
The simplest way to use the multicast API is to call: `lashup_gm_events:subscribe([Topic])`. You will then be streamed any update for this topic. You can send updates to a topic via `lashup_gm_mc:multicast(Topic, Data, Options)`. Where Topic is the aformentioned topic. Data is whatever you'd like. There are a few options available:
* record_route
* loop
* fanout
* TTL
* only_nodes

