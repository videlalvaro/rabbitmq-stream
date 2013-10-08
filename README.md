# RabbitMQ Stream Plugin #

TODO add description.

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

Enable the following plugins as explained the in the [RabbitMQ Plugin Development Guide](http://www.rabbitmq.com/plugin-development.html):

```erlang
[rabbitmq_management, amqp_client, rabbitmq_consistent_hash_exchange, random_exchange].
```

Then run `make run-in-broker`.

On a separate Terminal window run the following commands to start a second rabbit node.

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

You could repeat the previous two steps to start a couple more nodes. Don't forget to change the node name and port.

So far we have a RabbitMQ cluster. Now it's time to add a policy to tell RabbitMQ to make some exchanges as streams.

## Running the examples ##

To test the plugin you can run the `examples/shard.php` example.

First install composer as explained [here](http://getcomposer.org/doc/00-intro.md#installation-nix).

Then cd into the `examples` folder and run: `composer.phar install`.

Then run `php stream.php`.

That script will:

- Declare a policy for all exchanges named `"^shard\."`
- Create an exchange called `shard.logs_stream` of type `x-consistent-hash`
- Retrieve all stream queues on the broker
- Retrieve all stream queues on the broker for exchange `shard.logs_stream`
- Retrieve the local stream queue for exchange `shard.logs_stream`
- Retrieve a random stream queue for exchange `shard.logs_stream`