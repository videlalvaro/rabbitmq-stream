<?php

namespace RabbitMQUtils;

class RabbitMQUtils
{
    protected $client;
    protected $user;
    protected $pass;
    
    public function __construct($client, $user, $pass) {
        $this->client = $client;
        $this->user = $user;
        $this->pass = $pass;
    }
    
    public function request_nodes_info($info_items = array()) {
        $nodes = array();
        $columns = empty($info_items) ? '' : sprintf('?columns=%s', implode(',', $info_items));
        $response = $this->client->get(sprintf('/api/nodes%s', $columns))
                         ->setAuth($this->user, $this->pass)
                         ->send();
        if ($response->getStatusCode() == '200') {
            $data = $response->getBody();
            $nodes = json_decode($data, true);
        }
        
        return $this->value_or_exception($nodes, "Couldn't retrieve list of nodes");
    }
    
    public function get_host_part($name) {
        $parts = explode('@', $name);
        return $parts[1];
    }

    public function get_running_nodes($data) {
        return array_filter($data, function($n) {
            return $n['running'] == true;
        });
    }

    public function get_random_node($nodes) {
        $host = '';
        $key = array_rand($nodes);
        $host = $this->get_host_part($nodes[$key]['name']);
        
        return $this->value_or_exception($host, 'Error finding random node name to connect to');
    }
    
    public function get_random_rabbit_node() {
        $nodes = $this->request_nodes_info(array('name', 'running'));
        $running_nodes = $this->get_running_nodes($nodes);
        return $this->get_random_node($running_nodes);
    }

    public function get_local_rabbit_node($nodes, $local_node) {
        $host = '';
        foreach ($nodes as $n) {
            $n_host = $this->get_host_part($n['name']);
            if ($n_host == $local_node) {
                $host = $n_host;
                break;
            }
        }
        
        return $this->value_or_exception($host, sprintf("node %s is not running a RabbitMQ node\n", $local_node));
    }
    
    protected function value_or_exception($value, $message) {
        if (!empty($value)) {
            return $value;
        } else {
            throw new \Exception($message);
        }
    }
}