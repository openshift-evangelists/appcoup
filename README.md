# Kubernetes: Application Coupling

Demonstrates different application coupling options in Kubernetes.

Read also: https://blog.openshift.com/kubernetes-application-coupling/


## The application

Let's assume our application comprises two programs, a [generator](generator/generator.sh) program, appending random numbers to a file `data` like so:

```
$ docker run --rm -v "$PWD":/tmp/out -w /tmp/out alpine:3.6 sh -c 'tmpf=data && touch $tmpf && while true ; do echo $RANDOM >> $tmpf ; sleep 2 ; done ;'
```

As well as a simple [echo](echo/echo.sh) program, reading the generated numbers and serving it via HTTP on port `8000`:

```
$ docker run --rm -p 8000:8000 -v "$PWD":/tmp/in -w /tmp/in python:2.7 python -m SimpleHTTPServer
```

The application can then be consumed like so:

```
$ curl http://localhost:8000/data
4646
25543
3259
15121
...
```

## Coupling via Dockerfile

The tightest coupling is to put both programs into the same [Dockerfile](Dockerfile) like so:

```
FROM python:2.7-alpine
ADD ./generator/generator.sh /app/generator.sh
ADD ./echo/echo.sh /app/echo.sh
ADD app.sh /app/app.sh
WORKDIR /app
CMD ["sh", "app.sh"]
```

You can take this `Dockerfile`, build the container image, push it to a registry and deploy it using a pod.

## Coupling via a pod

Putting each of the application parts into a container image and launching them in a pod indeed allows us to have colocation as well as enable local communication. Let's start with the container images using the OpenShift [build process](https://docs.openshift.org/latest/dev_guide/builds/index.html) which will result in images available in the internal registry at `172.30.1.1:5000`.

For the `generator`, using a dedicated [Dockerfile](generator/Dockerfile):

```
$ cd generator/
$ oc new-build --strategy=docker --name='generator' .
$ oc start-build generator --from-dir .
```

And for the `echo` program, also using a dedicated [Dockerfile](echo/Dockerfile):

```
$ cd echo/
$ oc new-build --strategy=docker --name='echo' .
$ oc start-build echo --from-dir .
```

Next, I launch the two containers in a pod called `appcoup`, defined in [app-pod.yaml](app-pod.yaml):

```
$ oc create -f app-pod.yaml
```
