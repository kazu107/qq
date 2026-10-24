"use strict";
(() => {
  const el = id => document.getElementById(id);
  const language = new URLSearchParams(location.search).get('lang') === 'en' ? 'en' : 'ja';
  const t = (ja,en) => language === 'ja' ? ja : en;
  document.documentElement.lang=language;
  document.title='QueueQuest | '+t('無限ランキング','Infinite Rankings');
  const embedded = window.parent !== window;
  if (embedded) {
    document.body.classList.add('embedded');
    document.querySelector('header > a.secondary').addEventListener('click', event => { event.preventDefault(); window.parent.postMessage({type:'qq-service-open',kind:'account',language},location.origin); });
    document.querySelector('.brand').addEventListener('click', event => { event.preventDefault(); window.parent.postMessage({type:'qq-service-close'},location.origin); });
    window.addEventListener('message', event => { if(event.source===window.parent && event.origin===location.origin && ['qq-service-refresh','qq-profile-changed'].includes(event.data?.type)) refresh(); });
    document.addEventListener('keydown', event => { if(event.key==='Escape' && !document.querySelector('dialog[open]')) window.parent.postMessage({type:'qq-service-close'},location.origin); });
  }
  document.querySelector('header > a.secondary').href='/account?lang='+language;
  if(language==='en') {
    document.querySelectorAll('[data-en]').forEach(node=>{node.textContent=node.dataset.en;});
    document.querySelectorAll('thead th').forEach((node,index)=>{node.textContent=['Rank','Username','Score','Reached Step','Starter','Achieved'][index];});
  }
  const status = { active:t('中断中／送信中','Active / uploading'), pending:t('検証待ち','Pending verification'), verifying:t('検証中','Verifying'), verified:t('正式記録','Verified'), rejected:t('対象外','Ineligible'), disqualified:t('開発者操作などで対象外','Disqualified'), unverified:t('未検証・参考外','Unverified') };
  const monthLabel = id => {
    const month = /(\d{4})-(\d{2})$/.exec(id || '');
    return month ? (language === 'ja' ? `${month[1]}年${Number(month[2])}月` : `${month[1]}-${month[2]}`) : id;
  };
  const rulesLabel = id => /^infinite-\d+$/.test(id) ? t('ルール','Rules ')+id.slice(9) : id;
  let page = 0, initialized = false, serial = 0, selectedMonth = '', selectedRuleset = '', currentMonth = '', currentRuleset = '';
  async function refresh() {
    const current = ++serial;
    el('refresh').disabled = true;
    try {
      const query = new URLSearchParams({ season:selectedMonth, ruleset:selectedRuleset, starter:el('starter').value, page:String(page) });
      const response = await fetch('/api/ranked/board?' + query, { credentials:'same-origin', cache:'no-store', signal:AbortSignal.timeout(15000) });
      const data = await response.json();
      if (current !== serial) return;
      if (!response.ok) throw new Error();
      if (!selectedMonth && !selectedRuleset && currentMonth && (currentMonth !== data.season.id || currentRuleset !== data.rules.ruleset) && page > 0) {
        page=0; currentMonth=data.season.id; currentRuleset=data.rules.ruleset; refresh(); return;
      }
      currentMonth = data.season.id;
      currentRuleset = data.rules.ruleset;
      el('season').replaceChildren();
      for (const season of data.seasons) { const option=document.createElement('option'); option.value=season.id; option.textContent=monthLabel(season.id); el('season').append(option); }
      el('season').value=data.selection.season_id;
      el('ruleset').replaceChildren();
      for (const ruleset of data.seasons.find(season => season.id === data.selection.season_id)?.rulesets || [data.selection.ruleset]) {
        const option=document.createElement('option'); option.value=ruleset;
        option.textContent=rulesLabel(ruleset)+(ruleset === currentRuleset ? t('（現行）',' (current)') : ''); el('ruleset').append(option);
      }
      el('ruleset').value=data.selection.ruleset;
      if (!initialized) {
        for (const starter of data.rules.starters) { const option=document.createElement('option'); option.value=starter; option.textContent=data.catalog.starter[starter]?.[language] || starter; el('starter').append(option); }
        initialized=true;
      }
      el('entries').replaceChildren();
      for (const entry of data.entries) {
        const row=document.createElement('tr');
        for(const value of [entry.rank,entry.username,Number(entry.result.total_score).toLocaleString(),entry.result.reached_step,data.catalog.starter[entry.starter_id]?.[language] || entry.starter_id,new Date(entry.finished_at).toLocaleString(language==='ja'?'ja-JP':'en-US')]) {
          const cell=document.createElement('td'); cell.textContent=String(value); row.append(cell);
        }
        const button=document.createElement('button'); button.className='secondary'; button.textContent=entry.username;
        button.addEventListener('click',()=>{
          const result=entry.result;
          el('detail-name').textContent=entry.username+' / '+Number(result.total_score).toLocaleString()+t('点',' pts');
          el('detail-body').textContent=[`${monthLabel(entry.season_id)} / ${rulesLabel(entry.ruleset)}`,`${t('到達ステップ','Step')}: ${result.reached_step} / ${t('周回','Cycle')}: ${result.reached_cycle}`,`${t('踏破','Progress')}: ${result.progress} / ${t('ボス','Boss')}: ${result.boss} / ${t('挑戦','Challenge')}: ${result.challenge} / ${t('戦闘効率','Efficiency')}: ${result.efficiency}`,`${t('戦闘数','Battles')}: ${result.battle_count} / ${t('所持金','Gold')}: ${result.gold ?? '-'} / HP: ${result.hp ?? '-'}/${result.max_hp ?? '-'}`,`${t('最終ロードアウト','Final Loadout')}: ${(result.cards || []).map(id=>(data.catalog.card[id]?.[language] || id)+(result.card_upgrades?.[id] ? ' +'+result.card_upgrades[id] : '')).join(' / ')}`,`${t('遺物','Relics')}: ${(result.relics || []).map(id=>data.catalog.relic[id]?.[language] || id).join(' / ') || t('なし','None')}`].join('\n\n');
          el('details').showModal();
        });
        row.children[1].replaceChildren(button); el('entries').append(row);
      }
      el('notice').textContent=data.entries.length ? t('検証済み記録のみ表示しています。同点は同順位です。','Only verified records are listed. Equal scores share a rank.') : t('この条件の正式記録はまだありません。','No verified records match these filters yet.');
      el('self').textContent=data.self ? `${t('自分の順位','Your rank')}: ${data.self.rank}${t('位','')} / ${Number(data.self.result.total_score).toLocaleString()}${t('点',' pts')}` : t('この条件の自己ベストはまだありません。','You have no personal best for these filters yet.');
      el('page').textContent=String(page+1); el('previous').disabled=page===0; el('next').disabled=data.entries.length<50;
      const historyResponse=await fetch('/api/ranked/history',{credentials:'same-origin',cache:'no-store',signal:AbortSignal.timeout(10000)});
      if(current!==serial)return;
      el('history').replaceChildren();
      if(historyResponse.ok) {
        const history=await historyResponse.json();
        if(current!==serial)return;
        for(const run of history.runs) { const line=document.createElement('p'); line.textContent=`${monthLabel(run.season_id)} / ${rulesLabel(run.ruleset)} | ${status[run.status] || run.status} | ${data.catalog.starter[run.starter_id]?.[language] || run.starter_id} | ${run.result ? Number(run.result.total_score).toLocaleString()+t('点',' pts') : '-'}${run.reason ? ' | '+run.reason : ''}`; el('history').append(line); }
      } else el('history').textContent=t('ログインすると自分の履歴を確認できます。','Sign in to see your run history.');
    } catch { el('notice').textContent=t('ランキングを読み込めませんでした。通常プレイは引き続き利用できます。','Rankings are unavailable. Local play is unaffected.'); }
    finally { if(current===serial) el('refresh').disabled=false; }
  }
  el('refresh').addEventListener('click',refresh);
  el('season').addEventListener('change',()=>{selectedMonth=el('season').value === currentMonth ? '' : el('season').value;selectedRuleset='';page=0;refresh();});
  el('ruleset').addEventListener('change',()=>{
    selectedRuleset=el('ruleset').value === currentRuleset ? '' : el('ruleset').value;
    if(selectedRuleset && !selectedMonth) selectedMonth=el('season').value;
    else if(!selectedRuleset && el('season').value===currentMonth) selectedMonth='';
    page=0;refresh();
  });
  el('starter').addEventListener('change',()=>{page=0;refresh();});
  el('previous').addEventListener('click',()=>{page=Math.max(0,page-1);refresh();});
  el('next').addEventListener('click',()=>{page++;refresh();});
  el('close').addEventListener('click',()=>el('details').close());
  refresh();
})();
