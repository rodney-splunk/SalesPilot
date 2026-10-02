import assert from 'node:assert/strict';import {privateText,publicQuery,registerPrivateNames} from './privacy.mjs';
registerPrivateNames(['Jesse Yang','Nancy Xiao','Rodney White','José García','王小明']);
const source='Jesse Yang asked Nancy Xiao and 王小明 to email jesse@example.com or call +1 (415) 555-0199. José García said we ingest 45 GB daily. Rodney White mentioned Splunk Cloud.';
const masked=privateText(source);for(const value of ['Jesse Yang','Nancy Xiao','王小明','José García','jesse@example.com','555-0199','Rodney White'])assert.ok(!masked.text.includes(value));assert.equal(masked.restore(masked.text),source);assert.match(masked.text,/45 GB/);assert.match(masked.text,/Splunk Cloud/);assert.ok(!publicQuery(source).includes('PERSON_'));assert.match(privateText('api_key: abcdefghijklmnop').text,/SECRET REMOVED/);assert.equal(privateText('Nancy Xiaoling manages data').text,'Nancy Xiaoling manages data');console.log('PASS outbound current-call name, Unicode, email, phone and secret masking; exact-boundary guards; quantities and products retained');

for(const value of ['+44 20 7946 0958','4155550199','person@例子.公司'])assert.ok(!privateText(value).text.includes(value));
