# Blitzy

## build

```
$ mix escript.build
```

## use

blitzy expects 3 other nodes present: `b@127.0.0.1`, `c@127.0.0.1`, `d@127.0.0.1`.
You can start them with `iex --name <node_name> -S mix`.
Then `./blitzy` (the built executable) will allow help you run requests in distributed mode.
