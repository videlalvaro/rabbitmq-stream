# RabbitMQ Stream Plugin #

This plugin adds the concept of stream exchanges. The idea is that when you define a policy that makes an exchange a _stream_
the plugin will create one queue per node in the cluster. Messages published to the exchange will be delivered to the queues
either by consistent hashing or by a random algorithm (The plugin augments the _consistent-hash-exchange_ and the `random-exchange`
plugins).

## Why? ##

Why do we need this? RabbitMQ queues are bound to the node where they were first declared. This means that even if you create a cluster
of RabbitMQ brokers, at some point all message traffic will go to the node where the queue lives. What this plugin does is to give you
a centralized place where to send your messages, plus load balancing across many nodes, by adding queues to the other nodes in the cluster.

All the plumbing to __automatically maintain__ the stream queues is done by the plugin. If you add more nodes to the cluster, then the plugin
will __automatically create queues in those nodes__.

If you remove nodes from the cluster then RabbitMQ will take care of taking them out of the list of bound queues. Message loss can occur in the case 
where a race occurs from a node going away and your message arriving to the stream exchange. If you can't afford to lose a message then you can use
[publisher confirms](http://www.rabbitmq.com/confirms.html) to prevent message loss.

## How to get the queue name  to consume from? ##

With all these queues automatically added to the broker it can get tricky to know from which your consumer should get messages. The plugin adds a couple
of HTTP endpoints to help with that. See bellow.

## Ordering ##

Message order is maintained per stream queue, but not globally. If you need global ordering then stick with [mirrored queues](http://www.rabbitmq.com/ha.html).

## Building the plugin ##

Get the RabbitMQ Public Umbrella ready as explained in the [RabbitMQ Plugin Development Guide](http://www.rabbitmq.com/plugin-development.html).

Move to the umbrella folder an then run the following commands:

```bash
# the plugin allows routing via the random-exchange plugin
git clone https://github.com/videlalvaro/random-exchange.git
git clone bitbucket repo path
cd rabbitmq-stream
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

You could repeat the previous two steps to start a couple more nodes. Don't forget to change the `node name` and `port`.

So far we have a RabbitMQ cluster. Now it's time to add a policy to tell RabbitMQ to make some exchanges as streams.


```bash
../rabbitmq-server/scripts/rabbitmqctl -n rabbit-test@hostname set_policy my_stream "^shard\." '{"stream": "my_stream"}'
```

That policy will create a stream called `my_stream` for all exchanges whose name start with `shard.`.

Then if you declare an exchange called for example `shard.logs_stream` the plugin will create one queue per node in the cluster.
So if we have a cluster of nodes [rabbit1, rabbit2, rabbit3], we will get the following queues:

```
stream: shard.logs_stream - rabbit1@hostname
stream: shard.logs_stream - rabbit2@hostname
stream: shard.logs_stream - rabbit3@hostname
```
Each queue will be local to the cluster included in its name.

## Obtaining the queue to consume from ##

The plugin adds a couple of new HTTP API endpoints to the management plugin.

- __GET__ `/api/stream-queues/`: returns all the stream queues present in the broker.
- __GET__ `/api/stream-queues/vhost`: returns all the stream queues for `vhost`.
- __GET__ `/api/stream-queues/vhost/exchange`: returns all the stream queues for the `exchange` of `vhost`. 

The last API call accepts the optional parameter `node` which can be any of: 

- `local`: returns the stream queue that is local to the node where the HTTP call is made.
- `random`: returns a random stream queue from the queues belonging to the `exchange` stream.

## Running the examples ##

To test the plugin you can run the `examples/shard.php` example.

First install composer as explained [here](http://getcomposer.org/doc/00-intro.md#installation-nix).

Then `cd` into the `examples` folder and run: `composer.phar install`.

Then run `php stream.php`.

That script will:

- Declare a policy for all exchanges named `"^shard\."`
- Create an exchange called `shard.logs_stream` of type `x-consistent-hash`
- Retrieve all stream queues on the broker
- Retrieve all stream queues on the broker for exchange `shard.logs_stream`
- Retrieve the local stream queue for exchange `shard.logs_stream`
- Retrieve a random stream queue for exchange `shard.logs_stream`

## TODO ##

Adds parameters so the user can define an __amqpuri__ to use when declaring queues.