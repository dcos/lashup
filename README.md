# Lashup
[![Circle CI](https://circleci.com/gh/dcos/lashup.svg?style=svg&circle-token=e109b76cf8a017424100d9269640771210d7efe3)](https://circleci.com/gh/dcos/lashup)

### Background

Project Lashup is an underlying infrastructure system to enable Project Minuteman. The purpose of Project Lashup is to enable Project Minuteman to determine the list of available backends to fulfill a connection request. The purpose of Project Lashup in the context of Peacekeeper is to disseminate the list of IP, and Port endpoints. The system has to have strong availability performance properties, and availability properties. It is also known as the "Event Fabric".
Lashup will run on every agent. Most of the information needed can be derived from an Agent's TaskInfo, and TaskStatus.  Therefore, the initial version of Lashup's purpose is to advertise an up to date version of an Agent's Tasks. In addition to this, it must replicate this state to all other nodes running Lashup. This can be modeled as a key/value system, where every agent has its own namespace, that it, and only it can write to, but other agents can read from. The estimate of the information needed in TaskInfo is likely to be under a kilobyte, and the TaskStatus is likely to be under 512 kilobytes. Efficiencies can be taken in order to only advertise mutations, such as the work from the Delta-CRDT paper. 
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

