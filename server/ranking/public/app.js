"use strict";
(() => {
  const el = id => document.getElementById(id);
  const status = { active:'中断中／送信中', pending:'検証待ち', verifying:'検証中', verified:'正式記録', rejected:'対象外', disqualified:'開発者操作などで対象外', unverified:'未検証・参考外' };
  let page = 0, initialized = false, serial = 0;
  async function refresh() {
    const current = ++serial;
    el('refresh').disabled = true;
    try {
      const query = new URLSearchParams({ season:el('season').value, starter:el('starter').value, page:String(page) });
      const response = await fetch('/api/ranked/board?' + query, { credentials:'same-origin', cache:'no-store', signal:AbortSignal.timeout(15000) });
      const data = await response.json();
      if (current !== serial) return;
      if (!response.ok) throw new Error();
      if (!initialized) {
        for (const season of data.seasons) { const option=document.createElement('option'); option.value=season.id; option.textContent=season.id; el('season').append(option); }
        el('season').value=data.season.id;
        for (const starter of data.rules.starters) { const option=document.createElement('option'); option.value=starter; option.textContent=data.catalog.starter[starter]?.ja || starter; el('starter').append(option); }
        initialized=true;
      }
      el('entries').replaceChildren();
      for (const entry of data.entries) {
        const row=document.createElement('tr');
        for(const value of [entry.rank,entry.username,Number(entry.result.total_score).toLocaleString(),entry.result.reached_step,data.catalog.starter[entry.starter_id]?.ja || entry.starter_id,new Date(entry.finished_at).toLocaleString('ja-JP')]) {
          const cell=document.createElement('td'); cell.textContent=String(value); row.append(cell);
        }
        const button=document.createElement('button'); button.className='secondary'; button.textContent=entry.username;
        button.addEventListener('click',()=>{
          const result=entry.result;
          el('detail-name').textContent=entry.username+' / '+Number(result.total_score).toLocaleString()+'点';
          el('detail-body').textContent=[`到達ステップ: ${result.reached_step} / 周回: ${result.reached_cycle}`,`踏破: ${result.progress} / ボス: ${result.boss} / 挑戦: ${result.challenge} / 戦闘効率: ${result.efficiency}`,`戦闘数: ${result.battle_count}`,`最終ロードアウト: ${(result.cards || []).map(id=>data.catalog.card[id]?.ja || id).join(' / ')}`,`遺物: ${(result.relics || []).map(id=>data.catalog.relic[id]?.ja || id).join(' / ') || 'なし'}`].join('\n\n');
          el('details').showModal();
        });
        row.children[1].replaceChildren(button); el('entries').append(row);
      }
      el('notice').textContent=data.entries.length ? '検証済み記録のみ表示しています。同点は同順位です。' : 'この条件の正式記録はまだありません。';
      el('self').textContent=data.self ? `自分の順位: ${data.self.rank}位 / ${Number(data.self.result.total_score).toLocaleString()}点` : 'この条件の自己ベストはまだありません。';
      el('page').textContent=String(page+1); el('previous').disabled=page===0; el('next').disabled=data.entries.length<50;
      const historyResponse=await fetch('/api/ranked/history',{credentials:'same-origin',cache:'no-store',signal:AbortSignal.timeout(10000)});
      el('history').replaceChildren();
      if(historyResponse.ok) {
        const history=await historyResponse.json();
        for(const run of history.runs) { const line=document.createElement('p'); line.textContent=`${status[run.status] || run.status} | ${run.starter_id} | ${run.result ? Number(run.result.total_score).toLocaleString()+'点' : '-'}${run.reason ? ' | '+run.reason : ''}`; el('history').append(line); }
      } else el('history').textContent='ログインすると自分の履歴を確認できます。';
    } catch { el('notice').textContent='ランキングを読み込めませんでした。通常プレイは引き続き利用できます。'; }
    finally { if(current===serial) el('refresh').disabled=false; }
  }
  el('refresh').addEventListener('click',refresh);
  for(const id of ['season','starter']) el(id).addEventListener('change',()=>{page=0;refresh();});
  el('previous').addEventListener('click',()=>{page=Math.max(0,page-1);refresh();});
  el('next').addEventListener('click',()=>{page++;refresh();});
  el('close').addEventListener('click',()=>el('details').close());
  refresh();
})();
