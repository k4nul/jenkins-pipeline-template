# jenkins-controller

Contains the generic Jenkins deployment and service resources used when you want Jenkins inside the cluster.

This is a public-safe controller example, not a production controller baseline.
The deployment uses the floating `jenkins/jenkins:lts` image and ephemeral
`emptyDir` storage, so controller state is not durable. Pin images, define
durable storage, install plugins, configure credentials, and manage security
through your own controller or JCasC process before using Jenkins for real
workloads.

Default behavior:

- common ports only
- internal ClusterIP service
- separate JNLP service

Expose it through your own ingress, gateway, or load balancer strategy if you need external access.
