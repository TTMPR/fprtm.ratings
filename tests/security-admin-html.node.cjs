const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.resolve(__dirname,'../legacy.html'),'utf8');
const fragment = (start,end) => {
  const i = source.indexOf(start);
  const j = source.indexOf(end,i+start.length);
  assert.ok(i>=0 && j>i,'Missing isolated code '+start);
  return source.slice(i,j);
};
const escapeFn = fragment('function escHTML(s) {','function showNoticiasListView() {');

test('membership admin review treats submitted HTML as text, never executable markup', () => {
  const grid = {innerHTML:''};
  const reqs = [{
    id:1,created_at:'2026-10-20T00:00:00Z',type:'new',
    first_name:'<img src=x onerror=alert(1)>',last_name:'Test',
    email:'<svg onload=alert(2)>',phone:'"><img src=x>',
    sex:'M',club:'<b>Club',city:'<script>evil()</script>',
    state:'PR',country:'Puerto Rico',ath_confirmation:'"><img src=x onerror=alert(3)>',
    dob:'2000-01-01',guardian_name:'<iframe>',guardian_relation:'Padre',is_minor:true
  }];
  const context={document:{getElementById:(id)=>id==='requestsGrid'?grid:null},Date};
  vm.runInNewContext(escapeFn+'\n'+fragment('function renderPendingRequests(reqs) {','async function approveMembershipRequest(reqId) {')+'\nrenderPendingRequests(reqs)',{...context,reqs},{timeout:1500});
  assert.doesNotMatch(grid.innerHTML,/<img\s|<script\s|<svg\s|<iframe\s/i);
  assert.match(grid.innerHTML,/&lt;img/);
  assert.match(grid.innerHTML,/&lt;svg/);
  assert.match(grid.innerHTML,/&lt;script/);
});
test('club logo and labels cannot inject HTML or javascript images', () => {
  const context={_cirFmtDate:()=>'',Date};
  const out=vm.runInNewContext(escapeFn+'\n'+fragment('function _cirCardHTML(r, isHistory) {','async function renderClubInfoRequestsList() {')+'\n_cirCardHTML({id:1,status:"pending",club_name:"<img src=x>",solicitante:"<script>malicious()</script>",logo_url:"javascript:alert(1)",encargado:"<svg onload=alert(1)>",telefono:"(787)"},false)',context,{timeout:1500});
  assert.doesNotMatch(out,/<img\s|<script\s|<svg\s/i);
  assert.match(out,/&lt;img/);
  assert.match(out,/&lt;svg/);
  assert.doesNotMatch(out,/javascript:alert/);
});
test('other applicant panels escape untrusted labels and use data attributes for actions', () => {
  const club=fragment('async function showPendingClubChangesModal() {','function closePendingClubChangesModal() {');
  const submissions=fragment('async function loadRegSubmissions() {','async function openRegSubmissionDetail(id) {');
  const detail=fragment('async function openRegSubmissionDetail(id) {','async function approveRegSubmission(id) {');
  assert.match(club,/this\.dataset\.newClub/);
  assert.doesNotMatch(club,/r\.new_club\.replace\(/);
  assert.match(club,/escHTML\(r\.new_club\)/);
  assert.match(submissions,/escHTML\(r\.nombre\)/);
  assert.match(detail,/escHTML\(val\)/);
});
