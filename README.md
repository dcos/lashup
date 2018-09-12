# Lashup

[![CircleCI][circleci badge]][circleci]
[![Coverage][coverage badge]][covercov]
[![Jira][jira badge]][jira]
[![License][license badge]][license]
[![Erlang Versions][erlang version badge]][erlang]

## Summary

Lashup is a building block for a distributed control plane. It acts as a failure detector, a distributed fully-replicated CRDT store, and a multicast system. It isn't meant to be used by itself, but rather in conjunction with other components. In this it has several components described below. We currently use it in our [Minuteman Distributed Load Balancer](https://github.com/dcos/minuteman), and we've [publicly evaluated](https://github.com/dcos/minuteman#evaluation) its capability for fault tolerance with Minuteman.

### Overlay Builder

The core of Lashup is the overlay builder. This is a strongly connected, sparse graph of TCP connections used for communication. The primary reason to do this is scalability. If every node had to check the health of every other node, or maintain connections to every other node, we would quickly see scalability problems. In the code, these are the files prefixed with `lashup_hyparview`, as the implementation is heavily based on [HyParView](http://asc.di.fct.unl.pt/~jleitao/pdf/dsn07-leitao.pdf), but with a few changes:

1. Randomized timers are used instead of rounds.
2. A throttling mechanism is employed. We found that it takes longer for the overlay to become stable if joins are not throttled.
3. The overlay members are stored to disk and their health is occasionally checked.

### Routing & Failure Detection

Atop the overlay, we have a routing and failure detection layer. Each node in the Lashup network distributes its adjacencies to every other node in the system, and these are stored in memory. We found that at 1000 nodes, the typical size of this database is under 50 mb. The *fan-out* is set to **6** based on some static tunables in the overlay layer. Whenever there are changes to a given node's adjacency table, it gossips them throughout the network.

The nodes also check the health of one another. The health-check algorithm is an adaptive algorithm. We set the initial expected round trip time to 1 second. We then proceed to ping every one of our adjacencies every second. The historical round trip times are cached, and we use a logarithmic scale to determine how long future round trips should take. If a node fails to respond, we immediately disconnect it, and propagate that information through the gossip. At this point, all of the nodes that are also connected to that node proceed to check its health. This results in typical sub-second failure detection. If the overlay is unstable, the ping intervals are naturally elevated, and therefore inhibit rejection of nodes from the overlay.

Once we have this adjacency table, we then run a depth-first search on it to build a minimum spanning tree. This minimum spanning tree then becomes a mechanism to build sender-rooted multicast messages.

### Distributed Database

Lastly, and most interestingly, Lashup is a distributed database. Lashup acts as a CRDT store. It is built on top of Basho's [riak_dt](https://github.com/basho/riak_dt). Every key is replicated to every node. Rather than performing read-modify writes, the CRDT store offers operations. Specifically, you can operate on counters, maps, sets, flags, or registers. You can also compose these data structures to build a complex model. Given that Lashup isn't meant to work with a high key count, due to the naiveté of its anti-entropy algorithm, it is preferential to build a map.

The data is also persisted to disk via Mnesia. Mnesia was chosen due to its reliability, and testing in production, as well as the fact that it requires no dependencies outside of Erlang itself.

## Background

Lashup is an underlying infrastructure project of Minuteman. It enables Minuteman to determine the list of available backends to fulfill a connection request. In the context of project Peacekeeper, Lashup could disseminate the list of available IP and port endpoints. The system has to have strong availability performance properties, and availability properties. It is also known as the "Event Fabric".

Lashup runs on every agent in a cluster. Most of the information needed can be derived from a Mesos agent's `TaskInfo` and `TaskStatus` records.  Therefore, the initial goal of Lashup is to advertise up-to-date task records of an agent. In addition to this, it must replicate this state to all other nodes running Lashup. This can be modeled as a key-value system, where every agent has its own namespace, only it can write to, and other agents can read from. The estimate of the information used from a `TaskInfo` record is likely to be under a kilobyte, and the `TaskStatus` size is likely to be under 512 bytes. Efficiencies can be taken in order to advertise only mutations, such as the work from the [Delta-CRDT paper](http://arxiv.org/abs/1410.2803).

Since this information is used to make routing decisions, it must be disseminated in a timely manner. Lashup should provide strong guarantees about timely convergence not only under partial failure, but typical operating conditions. Although it is not a strong requirement, Lashup should also provide a mechanism to determine whether a replica (an agent) has entirely failed to avoid sending requests to it. It is likely that a different mechanism will have to be used for state dissemination versus liveness checking.

### Failure Detector

Prior to having a gossip protocol, Lashup needs to provide a failure detector for Minuteman. The purpose of the failure detector is to allow faster dissemination of data — whether it be through a cache, a broker, or something else. The reason for this is that agents can advertise their state independently of their health. Doing this allows us to handle stale data better because we can retire the advertised VIPs of agents more quickly than a period a epidemic-gossip system would take to disseminate said data.

We need a failure detector that's quick to converge (less than 1.5 seconds for disseminating a member failure to 90% of the cluster), and a failure detector that can detect asymmetric network partitions. For example, assume we have masters M1, M2, and M3, and agents A1, A2, A3, A4, and A5. We want to be able to detect the case where A[1-5] can communicate to M[1-3], but A[1-2] cannot communicate with A[3-5]. Ideally, we also want the failure detector to enable instigating health checks based on Minuteman connections. We do not want to mark any member of the set A[1-5] as failed if A[1-5] cannot communicate with M[1-3]. Such [network partitions happen often](https://queue.acm.org/detail.cfm?id=2655736). Many of these are caused by misconfiguration.

## Use-cases

### Detecting failures

The first obvious use-case for Lashup is to detect agent failures in the system. If we're sending traffic to a node via a load balancing mechanism, we can react to node failures faster than Mesos (10M) or other mechanisms can detect failure by using techniques like gossip, and indirect health checks. Alternatively, DCOS takes advantage of Mesos, which can have slow periods for detecting faults.

### Publishing VIPs

The second use-case for Lashup is to publish VIPs for Minuteman. These VIPs are derived by reading the local agent's `state.json`, and extracting the VIPs from it. The result of this is a map of sets. These maps can be simply merged across agents, with the merge operation for a set being a simple merge.

### Powering Novel Load Balancing Algorithms

Once there is a reliable failure detector, and a mechanism to disseminate data, it can be extended. Although we could trivially implement the local least connections, or global random balancing algorithm, such algorithms are quite often not the ideal mechanism for interactive web services. There is one algorithm that serves the purpose better: Microsoft's [Join-Idle-Queue](http://research.microsoft.com/apps/pubs/default.aspx?id=153348). It effectively requires a mechanism to expose queue depth to routers. Other algorithms, such as performance-based routing require very small amounts of metadata to be exposed, with very short update periods.

### Security

Security is being implemented by project Peacekeeper. Peacekeeper intercepts the first packet of every connection. The complexity is determining the destination. In order to determine the destination, the task list must be queried to find the task with a matching `NetworkInfo` record, and allocated ports. This information is difficult to cache, as it will have high churn, and overly aggressive caching can potentially lead to a security compromise.

In such a distributed filtering system, there is also a requirement to distribute the filtering rules to all of the nodes in a timely fashion, otherwise users can be left without connectivity, or users may have too much connectivity.

## Usage

Integrating Lashup into your own project is easy! You must set the configuration, `{mnesia, dir}` for the KV store to persist its data, and the `{lashup, work_dir}` to persist the Lamport clock used in the gossip algorithm. You must also configure contact nodes via `{lashup, contact_nodes}`. These nodes are used to bootstrap the overlay. At least one of them must be up for the new node to join.

### Membership

You can get the global membership snapshot by calling `lashup_gm:gm()`. If you're interested in finding out about changes in the global membership, you can subscribe to the `lashup_gm_events` `gen_event`. If you're interested in finding out reachability information, you can call `lashup_gm_route:get_tree(Origin)` to get the DFS tree from `Origin`. It returns a map, where the key is the destination node name, and the value is either the distance from the given origin, or `infinity`, if the node is unreachable.

### Key-Value Store

The key-value store exposes a traditional API, and a subscription API. You can request operations to the key-value store by simply executing `lashup_kv:request_op(Key, Op)`, where `Op` is a `riak_dt` operation. A few examples can be found in the [test suite](https://github.com/dcos/lashup/blob/master/test/lashup_kv_SUITE.erl).

#### Subscription API

The subscription API allows you to subscribe to key-value changes that match a specific pattern. We use standard `ets` match specs for this purpose. The match spec must return `true`. For example:
`ets:fun2ms(fun({[node_metadata|_]}) -> true end)`. The match spec must be a 1-tuple, where the only member of the tuple is a key pattern.

Then you can simply call `lashup_kv_events_helper:start_link(ets:fun2ms(fun({[node_metadata|_]}) -> true end))`. This will dump all existing keys matching the given pattern, and send you future keys matching the same pattern. In addition, Lashup deduplicates updates and only sends you new updates.

### Multicast

The simplest way to use the multicast API is to call `lashup_gm_events:subscribe([Topic])`. All updates to `Topic` are streamed to the caller. You can send updates to a topic via `lashup_gm_mc:multicast(Topic, Data, Options)`, where `Topic` is the aforementioned topic, and `Data` is whatever you'd like. There are a few options available:

* `record_route`
* `loop`
* `{fanout, Fanout}`
* `{ttl, TTL}`
* `{only_nodes, Nodes}`

<!-- Badges -->
[circleci badge]: https://img.shields.io/circleci/project/github/dcos/lashup/master.svg?style=flat-square
[coverage badge]: https://img.shields.io/codecov/c/github/dcos/lashup/master.svg?style=flat-square
[jira badge]: https://img.shields.io/badge/issues-jira-yellow.svg?style=flat-square
[license badge]: https://img.shields.io/github/license/dcos/lashup.svg?style=flat-square
[erlang version badge]: https://img.shields.io/badge/erlang-20.1-blue.svg?style=flat-square

<!-- Links -->
[circleci]: https://circleci.com/gh/dcos/lashup
[covercov]: https://codecov.io/gh/dcos/lashup
[jira]: https://jira.dcos.io/issues/?jql=component+%3D+networking+AND+project+%3D+DCOS_OSS
[license]: ./LICENSE
[erlang]: http://erlang.org/
