# RabbitMQ Stream Plugin #

This plugin adds the concept of stream exchanges. The idea is that when you define a policy that makes an exchange a _stream_,
the plugin will create at least one queue per node in the cluster (Think sharding, for some definition of sharding). 
Messages published to the exchange will be delivered to the queues either by __consistent hashing__ or by a __random algorithm__ 
(The plugin augments the `consistent-hash-exchange` and the `random-exchange` plugins).

## Why? ##

Why do we need this? RabbitMQ queues are bound to the node where they were first declared. This means that even if you create a cluster
of RabbitMQ brokers, at some point all message traffic will go to the node where the queue lives. What this plugin does is to give you
a centralized place where to send your messages, plus __load balancing__ across many nodes, by adding queues to the other nodes in the cluster.

The advantage of this setup is that the queues from where your consumers will get messages will be local to the node where they are connected.
On the other hand, the producers don't need to care about what's behind the exchange.

All the plumbing to __automatically maintain__ the stream queues is done by the plugin. If you add more nodes to the cluster, then the plugin
will __automatically create queues in those nodes__.

If you remove nodes from the cluster then RabbitMQ will take care of taking them out of the list of bound queues. Message loss can happen in the case 
where a race occurs from a node going away and your message arriving to the stream exchange. If you can't afford to lose a message then you can use
[publisher confirms](http://www.rabbitmq.com/confirms.html) to prevent message loss.

## How to get the queue name to consume from? ##

The plugin will randomly choose a local sharded queue during basic.consume.
See [bellow](https://github.com/videlalvaro/rabbitmq-stream#obtaining-the-queue-to-consume-from).

## Ordering ##

Message order is maintained per stream queue, but not globally. If you need global ordering then stick with [mirrored queues](http://www.rabbitmq.com/ha.html).

## Building the plugin ##

The plugin currently builds with a modified version of RabbitMQ that lives on the branch: `bug25817`. We are still discussing the design of the new
features proposed by that plugin. See [bellow](https://github.com/videlalvaro/rabbitmq-stream#bug25817-branch) for more details.

Get the RabbitMQ Public Umbrella ready as explained in the [RabbitMQ Plugin Development Guide](http://www.rabbitmq.com/plugin-development.html).

Move to the umbrella folder an then run the following commands, to fetch dependencies:

```bash
git clone https://github.com/videlalvaro/random-exchange.git
git clone https://github.com/rabbitmq/rabbitmq-consistent-hash-exchange.git
git clone https://videlalvaro@bitbucket.org/videlalvaro/rabbitmq-stream.git
cd rabbitmq-server
hg up bug25817
cd ../rabbitmq-stream
make
```
## Testing the plugin ##

Enable the following plugins as explained in the [RabbitMQ Plugin Development Guide](http://www.rabbitmq.com/plugin-development.html):

```erlang
[rabbitmq_management, amqp_client, rabbitmq_consistent_hash_exchange, random_exchange].
```

Then run `make run-in-broker`.

On a separate Terminal window run the following commands to start a second RabbitMQ node.

First setup the enabled plugins for the other node:

```bash
echo '[amqp_client,rabbitmq_consistent_hash_exchange,rabbitmq_stream, rabbitmq_management_agent, random_exchange].' > other_plugins
export RABBITMQ_ENABLED_PLUGINS_FILE=other_plugins
```

Then start the other node and cluster it:

```bash
make start-other-node OTHER_NODE=rabbit2 OTHER_PORT=5673
make cluster-other-node MAIN_NODE=rabbit-test@hostname OTHER_NODE=rabbit2
```

You could repeat the previous two steps to start a couple more nodes. Don't forget to change the `OTHER_NODE` and `OTHER_PORT` values.

So far we have a RabbitMQ cluster. Now it's time to add a policy to tell RabbitMQ to make some exchanges as streams.

First we will add a `stream-definition` parameter that will tell the plugin which user to use when declaring queues, how many shards per node
we want to create, and what's the routing key to use when binding the sharded queues to our exchange. If you use the consistent hash exchange
then the routing keys need to be "an integer as a string", since routing keys in AMQP must be strings.

```bash
../rabbitmq-server/scripts/rabbitmqctl set_parameter stream-definition my_stream '{"local-username": "guest", "shards-per-node": 2, "routing-key": "1234"}'
```
That parameter will tell the plugin to connect to RabbitMQ using the `guest`  username. It will then create 2 sharded queues per node. Based on the number
of cores in your server, you need to decide how many `shards-per-node` you want. And finally the routing key used in this case will be `"1234"`. That 
routing key will apply in the context of a consistent hash exchange.

Let's add our policy now:

```bash
../rabbitmq-server/scripts/rabbitmqctl -n rabbit-test@hostname set_policy my_stream "^shard\." '{"stream-definition": "my_stream"}'
```

That policy will create a stream called `my_stream` for all exchanges whose name start with `shard.`, whose `stream-definition` will be the one called
`my_stream` that we've just defined.

Then if you declare an exchange called for example `shard.logs_stream` the plugin will create two queues per node in the cluster.
So if we have a cluster of nodes [rabbit1, rabbit2, rabbit3], we will get the following queues in the cluster:

```
stream: shard.logs_stream - rabbit1@hostname - 0
stream: shard.logs_stream - rabbit1@hostname - 1

stream: shard.logs_stream - rabbit2@hostname - 0
stream: shard.logs_stream - rabbit2@hostname - 1

stream: shard.logs_stream - rabbit3@hostname - 0
stream: shard.logs_stream - rabbit3@hostname - 1
```
Each queue will be local to the node included in its name. Stream queues name will have the `stream:` prefix in their names, and an index suffix
starting at zero.

## Obtaining the queue to consume from ##

You can consume messages from sharded queues without needing to care about those strange queue names created by the plugin.

If you have a stream called `logs_stream`, then by sending a `basic.consume` call with the queue name `logs_stream`, the plugin will
figure out how to find the right queue from the stream to consume from. In other words, all those queues are transparent for the user.
The user only needs to publish messages to the `shard.logs_stream` exchange, and consume from a virtual queue called `shard.logs_stream`
as well.

### What strategy is used for picking the queue name ###

When you issue a `basic.consume`, the plugin will randomly choose a local sharded queue to return from. Of course the local sharded queue
will be part of the set of queues that belong to the chosen stream.

## Configuration parameters ##

The following configuration parameters affect the plugin behaviour:

- `local-username`: The username the plugin should use when connecting to RabbitMQ. The plugin connects to RabbitMQ to declare queues, for example. Defaults to RabbitMQ's `default_user`
- `shards-per-node`: How many sharded queues to create per node. This depends on the amount of cores in your server. Defaults to `1`.
- `routing-key`: The routing key used when the plugin binds the queues to the stream exchange. Defaults to `"10000"`.

First the parameters specified in the `stream-definition` applies, if not set there, then the plugin defaults to global parameters. Finally it will use the default plugin values.

To set a parameter for the plugin, you could use the following command:

```bash
rabbitmqctl set_parameter stream routing-key '"4321"'
```

That will set a global parameter for routing keys used by the plugin.

## Examples ##

Inside the `etc` folder you can find a set of shell scripts where you can see how to set the various policies and parameters supported by the plugin.

## Plugin Status ##

At the moment the plugin is __experimental__ in order to receive feedback from the community.

## bug25817 branch ##

This branch adds the concept of channel interceptors, to RabbitMQ. The idea is that while RabbitMQ is processing AMQP methods like `basic.consume` or
`queue.delete`, a plugin can intercept the method and modify the queue name.

This is useful in the case of this particular plugin, when the user might issue a `basic.consume('my_stream')`, but `my_stream` is actually a sharded queue.
The plugin then can inspect the provided queue name, decide if that's a sharded queue, and return a modified name to RabbitMQ with one of the queues 
managed by the plugin. 

Also a plugin can decide that a certain AMQP method can't be performed on a queue that's managed by the plugin. In this case declared a queue called `my_stream`
doesn't make much sense when there's actually a sharded queue by that name. In this case the plugin will return a channel error to the user.

The bug25817 branch makes the following methods to be intercepted. Next to them we detail this plugin behaviour.

- `'basic_consume', QueueName`: The plugin will randomly pick a sharded queue from the `QueueName` shard.
- `'basic_get', QueueName`: The plugin will randomly pick a sharded queue from the `QueueName` shard.
- `'queue_declare', QueueName`: The plugin forbids declaring queues with the same name of an existing shard, since `basic.consume` behaviour would be undefined.
- `'queue_bind', QueueName`: since there isn't an actual `QueueName` queue, this method returns a channel error.
- `'queue_unbind', QueueName`: since there isn't an actual `QueueName` queue, this method returns a channel error.
- `'queue_purge', QueueName`: since there isn't an actual `QueueName` queue, this method returns a channel error.
- `'queue_delete', QueueName`: since there isn't an actual `QueueName` queue, this method returns a channel error.

In the future, `queue.delete` and `queue.purge`, could delete the set of shards as a whole, and purge the set of shards as a whole, respectively.