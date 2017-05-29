# Kubernetes: Application Coupling

Very often, non-trivial applications consist of more than one executable, that is, have programs that need to be launched together in order to achieve some useful purpose. Whoa, that's a mouthful! Let's look at a concrete example which you may or may not consider useful, but for the sake of demonstration we'll use it since it has all the characteristics of a real-world setup.

Let's assume we have two programs, a `generator` program, appending random numbers to a file `data` like so:

```
$ docker run --rm -v "$PWD":/tmp/out -w /tmp/out alpine:3.6 sh -c 'tmpf=data && touch $tmpf && while true ; do echo $RANDOM >> $tmpf ; sleep 2 ; done ;'
```

As well as a simple `echo` program, reading the generated numbers and serving it via HTTP on port `8000`:

```
$ docker run --rm -p 8000:8000 -v "$PWD":/tmp/in -w /tmp/in python:2.7 python -m SimpleHTTPServer
```

The application, that is `generator` and `echo` together can then be consumed like so:

```
$ curl http://localhost:8000/data
4646
25543
3259
15121
...
```

Note that, in order to work, the `generator` and the `echo` program need to communicate, in our case via a shared file, and also, the HTTP API of `echo` program needs to be accessible.

The question is now: what options have you got to realize this application using Kubernetes? In the following we will discuss the available coupling options from tight coupling to loose coupling.

Note that while I'm taking advantage of the awesome build capabilities of OpenShift to simplify the container image build process, the coupling and with it the deployments are applicable to any Kubernetes setup.

## Coupling via Dockerfile

The tightest coupling is to put both programs into the same `Dockerfile` like so:

```
FROM python:2.7-alpine
ADD ./generator/generator.sh /app/generator.sh
ADD ./echo/echo.sh /app/echo.sh
ADD app.sh /app/app.sh
WORKDIR /app
CMD ["sh", "app.sh"]
```

You can take this `Dockerfile`, build the container image, push it to a registry and deploy it using a pod. In this pod, a single container would run with a couple of processes which you can verify by execing into the container:

```bash
/app # ps
PID   USER     TIME   COMMAND
    1 root       0:00 sh app.sh
    7 root       0:00 sh generator.sh
    8 root       0:00 sh echo.sh
   10 root       0:00 python -m SimpleHTTPServer
   32 root       0:00 sleep 2
   33 root       0:00 sh
   39 root       0:00 ps
```

This method has the advantage that all application parts are guaranteed to be scheduled on the same node, the communication between `generator` and `echo` program is trivially given since they run as processes in the same container. For many people, especially coming from non-cloud native environments, it's also easy to reason about what is going on.

There are also several disadvantage here:

1. We can only apply this method if we have access to the separate components. That is, if all of the programs are either available as binaries per se or even better the source code itself is under our control. If, however, one or more application components is only available as Docker image and we can not decompose it, we can't use this method.
1. If we change even only one of the programs, we have to re-build the entire image and re-deploy the application. That is, the components of the application can not independently evolve and also you can't re-use parts in an other context.
1. Last but not least health-checking is only available on the container level and that means we can't leverage the full power of Kubernetes to restart functional parts of the app, only the entire app.

Can we do better? Is there a method that preserves the advantages (colocation, sharing files and/or networking locally) while avoiding the disadvantages? Turns out that with pods we have such a method at hand.

## Coupling via a pod

Putting each of the application parts into a container image and launching them in a pod indeed allows us to have colocation (Kubernetes will schedule the containers on the same node) as well as enable local communication (since containers in the same pod can communicate via `localhost` and can share data via volumes).

Let's start with the container images; in the following I'm using the OpenShift [build process](https://docs.openshift.org/latest/dev_guide/builds/index.html) which will result in images available in the internal registry at `172.30.1.1:5000`.

For the `generator`:

```
$ cd generator/
$ oc new-build --strategy=docker --name='generator' .
$ oc start-build generator --from-dir .
```

And for the `echo` program:

```
$ cd echo/
$ oc new-build --strategy=docker --name='echo' .
$ oc start-build echo --from-dir .
```

Next, I launch the two containers in a pod called `appcoup`:

```
$ cat app-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: appcoup
spec:
  containers:
  - name: generator
    image: 172.30.1.1:5000/appcoup/generator:latest
    volumeMounts:
    - name: data
      mountPath: "/tmp/out"
  - name: echo
    image: 172.30.1.1:5000/appcoup/echo:latest
    ports:
    - containerPort: 8000
    volumeMounts:
    - name: data
      mountPath: "/tmp/in"
  volumes:
  - name: data
    emptyDir: {}

$ oc create -f app-pod.yaml
```

You can use `oc describe pod/appcoup` now to learn about details such as the pod's volume mounts, the pod ID or life cycle events (image pull, container started, etc.).

So, this is great. We still have the same locality guarantees as in the previous case such as that the programs are scheduled onto the same host or that `generator` can write to `/tmp/out/data` which is available for `echo` at `/tmp/in/data`. In addition, when we now extend or bug-fix the programs, we only need to build the container image for the one that has changed. Also, we can health-check the two containers independently and the `kubelet` can restart the as it sees fit, as well as services can route traffic selectively to containers that are in fact ready to serve traffic.

One limitation, however, still exists: whenever something changes we need to deploy a new version of the pod. While this might seem trivial, depending on the complexity of a program, this can mean a lot of network traffic to pull a new version of an image, or due to external dependency (for example, pulling the initial state from S3 or preparing a database).

What can we do to achieve even looser coupling?

## Loose Coupling

Kubernetes is very flexible when it comes to coupling and depending on the requirements of the data exchange (file I/O vs. networking) there are different options:

- Using `services`: if a program exposes, for example, an HTTP API you can use a [service](https://blog.openshift.com/kubernetes-services-by-example/) to provide a stable communication method including discovery via FQDNs. With this method, not only can parts of the application evolve separately but can also be upgraded independently. In our example application, this would however not work out-of-the-box, as the `generator` writes to disk, so it would require an adapter which can expose the `data` file via an HTTP interface in order for `echo` to consume it as well as `echo` itself would need to be adapted to be able to read from said API rather than from a file.
- Via `persistent volumes`: programs in different pods can mount [persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) to share data. In contrast to services, discovery in this case is a manual process, that is, requires out-of-band coordination how to get to the data, but is, particularly for high-volume data transfer a good option.
- Last but not least, logically connected programs might run in different clusters, leveraging [federation](https://kubernetes.io/docs/concepts/cluster-administration/federation/).

With this we conclude the post and I hope that it was a useful exercise, demonstrating the options available in Kubernetes to run applications, pertinent to ownership, colocation and communication requirements.
