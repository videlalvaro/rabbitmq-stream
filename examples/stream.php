<?php

require_once __DIR__.'/vendor/autoload.php';

use Guzzle\Http\Client;
use RabbitMQUtils\RabbitMQUtils;
use PhpAmqpLib\Connection\AMQPConnection;

$http_host = 'localhost';
$http_port = '15672';
$api_url = sprintf('http://%s:%s', $http_host, $http_port);

$host = 'localhost';
$port = 5672;
$user = 'guest';
$pass = 'guest';
$vhost = '/';

$client = new Client($api_url);

## add a policy
$policy = array('pattern' => "^shard\.", 'definition' => array('stream' => 'my_stream'));
$client->put('/api/policies/%2f/my_stream', 
             array('Content-Type' => 'application/json'), json_encode($policy))
       ->setAuth($user, $pass)
       ->send();

## declare exchange where policy applies
$exchange = 'shard.logs_stream';
$type = 'x-consistent-hash';

$conn = new AMQPConnection($host, $port, $user, $pass, $vhost);
$ch = $conn->channel();

$ch->exchange_declare($exchange, $type, false, true, false);

$ch->close();
$conn->close();

## gets all stream queues
echo "all queues\n";
$response = $client->get('/api/stream-queues')->setAuth($user, $pass)->send();
var_dump(json_decode($response->getBody(), true));

## gets all stream queues for a particular exchange
echo "$exchange\n";
$response = $client->get('/api/stream-queues/%2f/'.$exchange)->setAuth($user, $pass)->send();
var_dump(json_decode($response->getBody(), true));

## gets the queue local to the node where the API calls are made
echo "$exchange, local node\n";
$response = $client->get('/api/stream-queues/%2f/'.$exchange, array(), array('query' => array('node' => 'local')))
                     ->setAuth($user, $pass)
                     ->send();
var_dump(json_decode($response->getBody(), true));

## gets a random queue
echo "$exchange, random\n";
$response = $client->get('/api/stream-queues/%2f/'.$exchange, array(), array('query' => array('node' => 'random')))
                   ->setAuth($user, $pass)
                   ->send();
var_dump(json_decode($response->getBody(), true));