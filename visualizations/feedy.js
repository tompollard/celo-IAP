// npm install ws bignumber.js

const util = require('util');
const events = require('events');


const WebSocket = require('ws');
const BigNumber = require('bignumber.js');

const kGeth = "ws://35.233.175.45:8546/ws";
const kBlockScout = "https://mitiapstaging-blockscout.celo-networks-dev.org/";


function tlog(msg) {
  console.log((new Date()).toISOString() + " " + msg);
}

// Mapping of some of the events / transaction messages we are interested in.
// This is part of the ETH / Solidity ABI (keccak-256 hash of the signature).

let sigdict = {"04af2560":"userBids(address,address,address)","158ef93e":"initialized()","715018a6":"renounceOwnership()","7b103999":"registry()","8da5cb5b":"owner()","a4f1433c":"sortedBids(address,address)","a91ee0dc":"setRegistry(address)","aafb088e":"stageDuration()","affed0e0":"nonce()","e831be58":"pendingWithdrawals(address,address)","f2fde38b":"transferOwnership(address)","da35a26f":"initialize(uint256,address)","d1e76063":"setStageDuration(uint256)","056d380c":"reset(address,address)","62edcae8":"start(address,address,address,uint256)","90a08853":"commit(address,address,uint256,bytes32)","d2e06d16":"reveal(address,address,uint256,uint256,uint256,uint256)","dab3d742":"fill(address,address,uint256)","51cff8d9":"withdraw(address)","fe527edc":"getNumBids(address,address,address)","e1fe26a5":"getBidParams(address,address,address,uint256)","b1f7872f":"getStage(address,address)","54d2d402":"getAuctionParams(address,address)","4ea5014e":"stageStartTime(uint256,uint256,uint8)","db90cc2d5cdd2c25ea01e065395b401ab89b5064fd28a4b5a6d4c5b1aa767c81":"AuctionStarted(address,address,uint256,uint256,uint256,address,uint256)","509c675521ec7d4b747c41bb2181725e32efb1a3cef7a026b6e95c1ae52bfe50":"AuctionStageChanged(address,address,uint256,uint8)","d6d959909d722cf4a43540e718e2353ee9c39d1b07199e33b21b0f66bd8605e6":"Commit(address,address,address,uint256,uint256,uint256)","3b67285ec3b24442f44159b1aaa1d41560abbcd8fa3235d7fd8a2a94220c689f":"Reveal(address,address,address,uint256,uint256,uint256,uint256)","58b9d2001c95a893e2a0beb5ef569696c3daca96fe3f55470d6d45219a36c803":"Fill(address,address,address,uint256,uint256,uint256,uint256)","2717ead6b9200dd235aad468c9809ea400fe33ac69b5bfaa6d3e90fc922b6398":"Withdrawal(address,address,uint256)","27fe5f0c1c3b1ed427cc63d0f05759ffdecf9aec9e18d31ef366fc8a6cb5dc3b":"RegistrySet(address)","f8df31144d9c2f0f6b59d69b8b98abd5459d07f2742c4df920b25aae33c64820":"OwnershipRenounced(address)","8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0":"OwnershipTransferred(address,address)","63e047f6c744b74fb6176ae8e95a5d056f5bf82ffe806b6a70f381b44b7e6ece":"Commit(address,address,address,uint256,bytes32)","aa6fbca0b50b44ba485aef79eb18c66d3fa7181bcda59f81a0a4ec954094e1c8":"Reveal(address,address,address,uint256,uint256,bytes32)","e190fa40eda4f49a8e67dd86f6dd05d6f106ad9a5eae4424a6151af93cbe60f5":"Fill(address,address,address,uint256,uint256,bytes32)","03386ba3":"_setAndInitializeImplementation(address,bytes)","42404e07":"_getImplementation()","bb913f41":"_setImplementation(address)","d29d44ee":"_transferOwnership(address)","f7e6af80":"_getOwner()","50146d0e3c60aa1d17a70635b05494f864e86144a2201275021014fbf08bafe2":"OwnerSet(address)","ab64f92ab780ecbf4f3866f57cee465ff36c89450dcce20237ca7a8d81fb7d13":"ImplementationSet(address)","93a59077":"spreads(address,address)","8129fc1c":"initialize()","a532e748":"addTokenPair(address,address,uint256,uint256,uint256,uint256,uint256,uint256)","75ead459":"getSpread(address,address)","73d42fe4":"getBuyTokenAmount(address,address,uint256)","1dee47b3":"getSellTokenAmount(address,address,uint256)","afa99860":"getTokenPrice(address,address)","0ed2fc95":"exchange(address,address,uint256,uint256)","406a361d060f37c6b9220c9d8da1dfb078069f8dab53c70aa9625cafe0490fa5":"TokenPairAdded(address,address,uint256,uint256,uint256,uint256)","a6fee24309b1d83d9ec7b9e4dbb73c6f882746efbfb26db7b7d9e9f2fb6dc95a":"Exchange(address,address,address,uint256,uint256)","503fa44f":"exchangeRates(address,address)","de378f38":"setExchangeRate(address,address,uint256,uint256)","baaa61be":"getExchangeRate(address,address)","d0675b080f4d777cea1fd6b41821128760cbe794196648f8f0f5c160544d2270":"ExchangeRateSet(address,address,uint256,uint256)","c4d66de8":"initialize(address)","d48bfca7":"addToken(address)","5fa7b584":"removeToken(address)","950dad19":"burnToken(address)","6bec32da":"mintToken(address,address,uint256)","1c39c7d5":"transferGold(address,uint256)","45eb9077":"rebaseToken(address)","d6b34fd7":"exchangeGoldAndStableTokens(address,address,uint256,uint256)","e4860339":"tokens(address)"};

// Mapping of ERC-20 address to short name, _PEG is used for supply/demand rates.
const kERCName = {
  '0000000000000000000000000000000000000000000000000000000000000000': '_PEG',
  '000000000000000000000000000000000000000000000000000000000000ce10': 'cGLD',
  '0000000000000000000000009a9f0ac7e4668a094f0be966f8eb79d6ad166e61': 'cUSD',
};

function fromhexi(x) {
  return BigNumber(x, 16).toNumber();
}

function fromwei(x) {
  return BigNumber(x, 16).shiftedBy(-18).toString();
}

function fromwei_f(x) {
  return BigNumber(x, 16).shiftedBy(-18).toNumber();
}

function exrate_f(a, b) {
  let af = fromwei_f(a), bf = fromwei_f(b);
  return af / bf;
}

function exrate_fmt(a, b) {
  let af = fromwei_f(a), bf = fromwei_f(b);
  if (bf === 0) return '-';
  let str = (af / bf).toFixed(4);
  return str;
}

function ercname(x) {
  return kERCName[x] || x;
}

function parse_event(x) {
  let sighash = x.topics[0].substr(2);
  let rest = x.data.substr(2).match(/.{64}/g);  // 32 bits (64 hex)
  let topics = x.topics.slice(1);
  topics = topics.map(x => x.substr(2));  // remove the 0x prefix
  rest = topics.concat(rest);  // indexed inputs
  let sig = sigdict[sighash];

  let fname = (sig || 'unknown').split('(')[0];

  let record = {
    transactionHash: x.transactionHash,
    transactionIndex: x.transactionIndex,
    blockHash: x.blockHash,
    blockNumber: x.blockNumber,
    logIndex: x.logIndex,

    type: 'event',
    name: fname,
    args: rest,
  };

  switch (fname) {
    case 'Commit': case 'Reveal': case 'Fill':
      record.address = '0x' + topics[2].substr(-40);
      break;
    case 'Exchange':
      record.address = '0x' + topics[0].substr(-40);
      break;
    case 'Withdrawal':
      record.address = '0x' + topics[1].substr(-40);
      break;
  }

  switch (fname) {
    case 'Reveal': case 'Fill':
    {
      record.weiValue0 = rest[4]; record.weiValue1 = rest[5];
      let a = fromwei_f(record.weiValue0), b = fromwei_f(record.weiValue1);
      record.approxValue0 = a; record.approxValue1 = b;
      record.approxExchangeRate = a / b;
      break;
    }
    case 'Exchange':
    {
      record.weiValue0 = rest[4]; record.weiValue1 = rest[3];
      let a = fromwei_f(record.weiValue0), b = fromwei_f(record.weiValue1);
      record.approxValue0 = a; record.approxValue1 = b;
      record.approxExchangeRate = a / b;
      break;
    }
    case 'ExchangeRateSet':
    {
      record.weiValue0 = rest[2]; record.weiValue1 = rest[3];
      let a = fromwei_f(record.weiValue0), b = fromwei_f(record.weiValue1);
      record.approxValue0 = a; record.approxValue1 = b;
      record.approxExchangeRate = a / b;
      break;
    }
    case 'Withdrawal':
    {
      record.weiValue0 = rest[2];
      record.approxValue0 = fromwei_f(record.weiValue0);
      break;
    }
    case 'AuctionStarted':
    {
      record.weiValue0 = rest[6];
      record.approxValue0 = fromwei_f(record.weiValue0);
      break;
    }
    case 'Commit':
    {
      record.weiValue0 = rest[4];
      record.approxValue0 = fromwei_f(record.weiValue0);
      break;
    }
  }

  switch (fname) {
    case 'Commit':
      // converting 0 (selling) -> 1 (buying)
      record.ercName0 = ercname(rest[0]);
      record.ercName1 = ercname(rest[1]);
      record.auctionNonce = fromhexi(rest[3]);
      record.auctionBidIndex = fromhexi(rest[5]);
      break;
    case 'Reveal':
      record.ercName0 = ercname(rest[0]);
      record.ercName1 = ercname(rest[1]);
      record.auctionNonce = fromhexi(rest[3]);
      record.auctionBidIndex = fromhexi(rest[6]);
      break;
    case 'Fill':
      record.ercName0 = ercname(rest[0]);
      record.ercName1 = ercname(rest[1]);
      record.auctionNonce = fromhexi(rest[3]);
      record.auctionBidIndex = fromhexi(rest[6]);
      break;
    case 'Withdrawal':
      record.ercName0 = ercname(rest[0]);
      break;
    case 'Exchange':
      record.ercName0 = ercname(rest[2]);
      record.ercName1 = ercname(rest[1]);
      break;
    case 'AuctionStageChanged':
      record.ercName0 = ercname(rest[0]);
      record.ercName1 = ercname(rest[1]);
      record.auctionNonce = fromhexi(rest[2]);
      break;
    case 'AuctionStarted':
      record.ercName0 = ercname(rest[0]);
      record.ercName1 = ercname(rest[1]);
      record.auctionNonce = fromhexi(rest[2]);
      break;
    case 'ExchangeRateSet':
      record.ercName0 = ercname(rest[0]);
      record.ercName1 = ercname(rest[1]);
      break;
  }

  switch (fname) {
    case 'AuctionStageChanged':
      //  0 Reset,
      //  1 Commit,
      //  2 Reveal,
      //  3 Fill,
      //  4 Ended
      record.auctionStageName = ["Reset", "Commit", "Reveal", "Fill", "Ended"][parseInt(rest[3], 16)];
      break;
  }

  return record;
}

// Small helper to combine multiple (serial) getLogs calls.
function do_logs_rpc_chain(conn, cb, chain, out=[]) {
  if (chain.length <= 0) {
    cb({result: out.map(x => x.result).reduce((a, b) => a.concat(b))});
    return;
  }

  let [addr, hash] = chain.pop().split(':');
  conn.doRPC("eth_getLogs", {fromBlock: "0x0", topics: ["0x" + hash], address: "0x" + addr}, res => {
    out.push(res);
    do_logs_rpc_chain(conn, cb, chain, out);
  });
}

function WebSocketConnectivity(url) {
  this.ws = null;
  this.url = url;
  this.rpc_id = 0;
  this.waiting = { };
  this.subs = { };

  this.records = [ ];
  this.known = new Set();  // for de-dup

  // It's a bit racey between getting all historical data and subscribing to
  // new updates (and there isn't a way via geth to do it in some sort of
  // atomic way), so we subscribe first, then get historical data and buffer
  // and updates until the historical data is loaded.  We need to make sure
  // to handle possible duplication between the two.
  this.hist_loaded = false;
  this.buffered = [ ];
}

util.inherits(WebSocketConnectivity, events.EventEmitter);

WebSocketConnectivity.prototype.start = function() {
  let ws = this.ws = new WebSocket(this.url);

  ws.on('message', e => {
    let res = JSON.parse(e);
    if (res.method === "eth_subscription") {
      let id = res.params.subscription;
      let cb = this.subs[id];
      if (cb) cb(res);
      return;
    }

    let cb = this.waiting[res.id];
    delete this.waiting[res.id];
    if (cb) cb(res);
  });

  // NOTE: fetchHistorical will mutate chain
  let chain = [
    '1eb806d40b102ac71ffb5b3f4bef8a049ea09de7:db90cc2d5cdd2c25ea01e065395b401ab89b5064fd28a4b5a6d4c5b1aa767c81',  // AuctionStarted
    '1eb806d40b102ac71ffb5b3f4bef8a049ea09de7:509c675521ec7d4b747c41bb2181725e32efb1a3cef7a026b6e95c1ae52bfe50',  // AuctionStageChanged
    '1eb806d40b102ac71ffb5b3f4bef8a049ea09de7:d6d959909d722cf4a43540e718e2353ee9c39d1b07199e33b21b0f66bd8605e6',  // Commit
    '1eb806d40b102ac71ffb5b3f4bef8a049ea09de7:3b67285ec3b24442f44159b1aaa1d41560abbcd8fa3235d7fd8a2a94220c689f',  // Reveal
    '1eb806d40b102ac71ffb5b3f4bef8a049ea09de7:58b9d2001c95a893e2a0beb5ef569696c3daca96fe3f55470d6d45219a36c803',  // Fill
    '1eb806d40b102ac71ffb5b3f4bef8a049ea09de7:2717ead6b9200dd235aad468c9809ea400fe33ac69b5bfaa6d3e90fc922b6398',  // Withdrawal
    'b1e52539adedb96aaefb970e6b985990868880ec:a6fee24309b1d83d9ec7b9e4dbb73c6f882746efbfb26db7b7d9e9f2fb6dc95a',  // uniswap
    '04f2e8af89391c93557353cec7ec7826829d06ef:d0675b080f4d777cea1fd6b41821128760cbe794196648f8f0f5c160544d2270',  // exchange rate
  ];

  ws.on('open', () => {
    tlog('geth ws opened ' + this.url);

    // See https://github.com/ethereum/go-ethereum/wiki/RPC-PUB-SUB
    let filter = {
      topics: [chain.map(x => '0x' + x.split(':')[1])],
      address: chain.map(x => '0x' + x.split(':')[0]),
    };
    this.doRPCRawParams("eth_subscribe", ["logs", filter], res => {
      //console.log(res);
      tlog("created update subscription: " + res.result);
      this.subscribe(res.result, res => {
        if (!this.hist_loaded) {
          tlog("Buffering update until historical data is loaded...");
          this.buffered.push(res);
        } else {
          //console.log(res);
          //console.log(parse_event(res.params.result));
          this.onEvent(res);
        }
      });
      this.fetchHistorical(chain);
    });

    /*
    this.doRPCRawParams("eth_subscribe", ["newPendingTransactions"], res => {
      //console.log(res);
      tlog("created newPendingTransactions subscription: " + res.result);
      this.subscribe(res.result, res => {
        console.log(res);
        this.doRPC("eth_getTransactionByHash", res.params.result, res => {
          console.log(res);
        });
      });
    });
    */
  });
};

WebSocketConnectivity.prototype.addParsedRecord = function(record) {
  let key = record.transactionHash + '_' + record.logIndex;
  if (this.known.has(key)) {
    tlog('Duplicate event for key: ' + key);
    return false;
  } else {
    this.known.add(key);
    this.records.push(record);
    return true;
  }
};

WebSocketConnectivity.prototype.onEvent = function(res) {
  //console.log(res);
  let parsed = parse_event(res.params.result);
  if (this.addParsedRecord(parsed)) {
    //console.log(parsed);
    this.emit('event', parsed);
  }
};

WebSocketConnectivity.prototype.fetchHistorical = function(chain) {
  tlog("fetchHistorical() running...");

  let done = (res) => {
    res = res.result;
    tlog("fetchHistorical() done fetch " + res.length + " records");

    function sorter(a, b) {
      let ab = parseInt(a.blockNumber, 16);
      let bb = parseInt(b.blockNumber, 16);
      if (ab !== bb) return ab - bb;
      // https://github.com/ethereum/go-ethereum/issues/2028
      return parseInt(a.logIndex, 16) - parseInt(b.logIndex, 16);
    }

    res.sort(sorter);
    //res.reverse();

    for (let i = 0, il = res.length; i < il; ++i) {
      let x = res[i];
      let record = parse_event(x);
      this.addParsedRecord(record);
    }

    tlog("fetchHistorical() done parse " + this.records.length + " records");
    this.hist_loaded = true;
    while (this.buffered.length > 0) this.onEvent(this.buffered.shift());
  }

  do_logs_rpc_chain(this, done, chain);
};

WebSocketConnectivity.prototype.doRPCRawParams = function(meth, params, cb) {
  let id = this.rpc_id++;
  this.waiting[id] = cb;
  let json = JSON.stringify({
    jsonrpc: "2.0",
    method: meth,
    params: params,
    id: id});
  this.ws.send(json);
};

WebSocketConnectivity.prototype.doRPC = function(meth, params, cb) {
  return this.doRPCRawParams(meth, [params], cb);
};

WebSocketConnectivity.prototype.subscribe = function(id, cb) {
  this.subs[id] = cb;  // NOTE overwrites
};

function FeedyWebSocketServer(conn, opts) {
  this.ws = null;
  this.conn = conn;
  this.opts = opts;

  this.clients = [ ];
}

FeedyWebSocketServer.prototype.start = function() {
  tlog("Starting server at ws://" + this.opts.host + ":" + this.opts.port);
  this.ws = new WebSocket.Server(this.opts);

  this.conn.on('event', e => {
    let cs = this.clients;
    let msg = JSON.stringify(e);
    for (let i = 0, il = cs.length; i < il; ++i) {
      let c = cs[i].client;
      try { c.send(msg); } catch(e) { tlog(e); }
    }
  });

  // maybe_req is the request only starting with ws v3
  this.ws.on('connection', (client, maybe_req) => {
    if (!this.conn.hist_loaded) {
      tlog("Killing client, not ready yet...");
      client.close();
      return;
    }
    let isfull = (maybe_req || client.upgradeReq).url === "/full";
    this.clients.push({full: isfull, client: client});
    if (isfull) {
      client.send(JSON.stringify({type: 'snapshot', records: this.conn.records}));
    }
    client.on('message', msg => {
      // one way for now...
    });
    client.on('error', msg => {
      tlog("client error");
      client.close();
    });
    client.on('close', msg => {
      tlog("client close");
      this.clients = this.clients.filter(x => x.client !== client);
    });
  });
};

let g_conn = new WebSocketConnectivity(kGeth);
g_conn.start();
let g_server = new FeedyWebSocketServer(g_conn, {host: '127.0.0.1', port: 8099});
g_server.start();
