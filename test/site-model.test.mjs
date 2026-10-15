import {test} from 'node:test';
import assert from 'node:assert/strict';
import {rangeModel,normalizeCoin,safeUrl,marketNumber,addressValue,formatUsd} from '../site/assets/model.js';

test('Every allowed range is symmetric, bounded and monotonic; bees match the tier',()=>{
  let prior=0;
  for(let width=5;width<=80;width++){
    const model=rangeModel(width);
    assert.ok(Math.abs(model.lower+model.upper-2)<1e-12);
    assert.ok(model.lower>0&&model.upper<2);
    assert.ok(model.flowerScale>prior);prior=model.flowerScale;
    assert.equal(model.tier,width<20?'narrow':width<50?'balanced':'wide');
    assert.equal(model.chartHalf,width*3);
  }
});
test('Bad and out-of-bounds calculator inputs stay deterministic',()=>{
  assert.equal(rangeModel(NaN).width,30);
  assert.equal(rangeModel(-200).width,5);
  assert.equal(rangeModel(9000).width,80);
  assert.equal(rangeModel(12.6).width,13);
});
test('Missing data stays missing; numeric zero is a real value',()=>{
  const empty=normalizeCoin({},'https://example.test');
  assert.equal(empty.token,null);assert.equal(empty.coinUrl,null);
  assert.deepEqual(empty.market,{priceUsd:null,marketCap:null,volume24h:null});
  for(const invalid of [NaN,Infinity,-1,'123',null,undefined])assert.equal(marketNumber(invalid),null);
  assert.equal(marketNumber(0),0);
});
test('Runtime links reject script schemes, credentials and insecure remote destinations',()=>{
  for(const value of ['javascript:alert(1)','data:text/html,hi','http://other.test','https://name:pass@example.test'])assert.equal(safeUrl(value,'https://example.test'),null);
  assert.equal(safeUrl('/coin/launch','https://example.test'),'https://example.test/coin/launch');
  assert.equal(safeUrl('https://chart.example.test','https://example.test'),'https://chart.example.test/');
});
test('A token must be a complete nonzero address and is never inferred',()=>{
  assert.equal(addressValue('launching…'),null);
  assert.equal(addressValue('0x0000000000000000000000000000000000000000'),null);
  assert.equal(addressValue('0x123'),null);
  // The supplied pair address is only a parser fixture, never a SUN address in the export.
  const address='0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127';
  assert.equal(normalizeCoin({token:address},'https://example.test').token,address);
});
test('Small nonzero prices never round to an apparent zero',()=>{
  assert.notEqual(formatUsd(1e-14,true),'$0.00');
  assert.equal(formatUsd(0,true),'$0.00');
  assert.equal(formatUsd(2500),'$2.5K');
});
