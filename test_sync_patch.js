// test_sync_patch.js — A/B test: hành vi TRƯỚC và SAU khi vá (chạy trên bản đã bung)
// Dùng: node test_sync_patch.js <thư_mục_app>
const fs = require('fs');
const path = require('path');

const APP = process.argv[2] || path.join(process.env.HOME, 'zalo/test-root/app');
const swPatched = fs.readdirSync(path.join(APP, 'pc-dist')).find(f => /^shared-worker\.[a-f0-9]+\.js$/.test(f));
const dir = path.join(APP, 'pc-dist', swPatched);
const orig = fs.readFileSync(dir + '.orig', 'utf8');
const patched = fs.readFileSync(dir, 'utf8');

const RX_HEAD = /if\(s===ee\.MSG_UNKNOWN\)return void 0;let r=e\.parsedIdTo\|\|this\.idStore\.get\(e\.ownerId\),i=e\.parsedUidFrom\|\|e\.fromId==e\.userId\?"0":this\.idStore\.get\(e\.fromId\);if\(!i\|\|!r\)return void 0;let n=e\.msg,a=e\.attachData;/;
const RX_HEAD_PATCHED = /if\(s===ee\.MSG_UNKNOWN\)return void 0;const m=e=>[\s\S]*?Object\.assign\(a\.attach,c0\.data\)\);/;

function headFrom(src, rx, label) {
  const m = src.match(rx);
  if (!m) throw new Error('Không trích được đoạn đầu hàm (' + label + ')');
  return m[0];
}

function runHead(head, e, ctx) {
  const body = 'const ee = { MSG_UNKNOWN: "__UNKNOWN__" };\nconst s = ' + JSON.stringify(e.__s) + ';\n' + head + '\nreturn { r: (typeof r!=="undefined"?r:undefined), i:(typeof i!=="undefined"?i:undefined), n:(typeof n!=="undefined"?n:undefined), a:(typeof a!=="undefined"?a:undefined) };';
  const f = new Function('e', body);
  return f.call(ctx, e);
}

const CTS = { s: 'MSG_TEXT' }; // giá trị đại diện cho e.parsedType

function mkRow(msg) {
  return {
    __s: CTS.s,
    globalMsgId: 1001,
    ownerId: 9999,          // id "ồn" chưa có trong idStore (đúng tình huống lúc khôi phục)
    fromId: 555,
    userId: 'me-000',
    msg: msg,
    attachData: {},
  };
}

const ctxEmpty = { idStore: new Map() }; // bảng ánh xạ RỖNG = lúc đồng bộ lần đầu
const ctxFull = { idStore: new Map([[9999, 'own-noise'], [555, 'from-noise']]) };

console.log('== A/B TEST: crossMsgToNormalMsg (đoạn logic đã vá) ==\n');

const headO = headFrom(orig, RX_HEAD, 'orig');
const headP = headFrom(patched, RX_HEAD_PATCHED, 'patched');

// 1) idStore rỗng (đồng bộ lần đầu từ điện thoại)
let rO = runHead(headO, mkRow('xin chào'), ctxEmpty);
let rP = runHead(headP, mkRow('xin chào'), ctxEmpty);
console.log('[1] idStore RỖNG (lúc khôi phục từ điện thoại)');
console.log('    TRƯỚC khi vá:', rO === undefined ? 'undefined  -> TIN NHẮN B BỎ RƠI' : JSON.stringify(rO));
console.log('    SAU khi vá  :', rP === undefined ? 'undefined -> vẫn bỏ' : 'giữ lại: fromId=' + rP.i + ' ownerId=' + rP.r);
console.log('    => ' + (rO === undefined && rP !== undefined ? 'ĐÃ SỬA ĐƯỢC LỖI MẤT TIN NHẮN' : '!! KIỂM TRA LẠI'));

// 2) idStore có dữ liệu
rO = runHead(headO, mkRow('xin chào'), ctxFull);
rP = runHead(headP, mkRow('xin chào'), ctxFull);
console.log('\n[2] idStore ĐÃ CÓ ánh xạ (không được đổi hành vi cũ)');
console.log('    TRƯC:', rO === undefined ? 'undefined' : 'fromId=' + rO.i + ' ownerId=' + rO.r);
console.log('    SAU  :', rP === undefined ? 'undefined' : 'fromId=' + rP.i + ' ownerId=' + rP.r);
console.log('    => ' + (rO && rP && rO.i === rP.i && rO.r === rP.r ? 'GIỮ NGUYÊN hành vi cũ (ánh xạ noise-id vẫn được ưu tiên)' : '!! KIỂM TRA LẠI'));

// 3) giải mã JSON trong msg + trộn vào attach
const rowJson = mkRow('{"action":"rtf"}||{"data":{"catId":7,"title":"ảnh"}}');
rO = runHead(headO, rowJson, ctxEmpty);
rP = runHead(headP, rowJson, ctxEmpty);
const okAttach = rP && rP.a && rP.a.attach && rP.a.attach.catId === 7;
console.log('\n[3] msg chứa JSON sau "||" (tin nhắn có đính kèm khi khôi phục)');
console.log('    SAU khi vá: n=' + JSON.stringify(rP ? String(rP.n).slice(0, 40) : null) + ' attach=' + JSON.stringify(rP ? rP.a.attach : null));
console.log('    => ' + (okAttach ? 'ĐÃ tách JSON và trộn vào attach (OK)' : '!! chưa trộn được attach'));

// 4) chuẩn hoá id nhóm trong convertCrossV2ToCrossV1
const RX_IIFE = /,\(_f=>\{[\s\S]*?\}\)\(\)/;
const m = patched.match(RX_IIFE);
console.log('\n[4] Chuẩn hoá id nhóm ("g123" -> "123") trong convertCrossV2ToCrossV1');
if (!m) {
  console.log('    !! không trích được đoạn trả về');
} else {
  const expr = m[0].slice(1); // bỏ dấu phẩy đầu
  const build = new Function('e', 'r', 't', 'return ' + expr + ';');
  const out = build.call({ backupConvId: '1755123456789', noiseId: 'noise-1', plainUserId: 'me-000' },
    { SenderId: 'g123456', OwnerId: 'g789012', GlbMsgId: 5, CliMsgId: 6, MsgContent: 'hi', TimeStamp: 123, TTL: 0, MsgType: 1 },
    {}, 'text');
  console.log('    Kết quả:', JSON.stringify({ fromId: out.fromId, ownerId: out.ownerId, localPathRaw: out.localPathRaw, type: out.type }));
  console.log('    => ' + (out.fromId === '123456' && out.ownerId === '789012' ? 'Chuẩn hoá ĐÚNG (bỏ tiền tố g)' : '!! chuẩn hoá sai'));
}

// 5) khôi phục hội thoại: noiseIdStore rỗng
console.log('\n[5] Khôi phục danh sách hội thoại khi chưa có ánh xạ noiseId');
const beforeLine = /if\(t\)\{const s=1===e\.ownerType,r=\{plainId:e\.ownerId,noisedId:t/;
console.log('    TRƯỚC khi vá: hội thoại vào nhánh else -> bị đưa vào danh sách "thiếu" (g.push) và KHÔNG hiện');
console.log('    SAU khi vá  : noiseIdStore.get(ownerId)||ownerId -> luôn có giá trị, hội thoại được giữ');
console.log('    => ' + (patched.includes('this.noiseIdStore.get(e.ownerId)||e.ownerId') ? 'ĐÃ vá (đã xác nhận trong file)' : '!! chưa vá'));