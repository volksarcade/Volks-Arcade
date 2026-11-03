import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl=Deno.env.get('SUPABASE_URL')!;
const anonKey=Deno.env.get('SUPABASE_ANON_KEY')!;
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const allowedOrigins=new Set(['https://volksarcade.github.io','http://localhost:3000','http://127.0.0.1:3000']);
const userClient=createClient(supabaseUrl,anonKey,{auth:{persistSession:false,autoRefreshToken:false}});
const admin=createClient(supabaseUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
function respond(body:unknown,status:number,origin:string|null){
  const headers:Record<string,string>={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
  if(origin&&allowedOrigins.has(origin)){headers['Access-Control-Allow-Origin']=origin;headers['Access-Control-Allow-Headers']='authorization,apikey,content-type,x-client-info';headers['Access-Control-Allow-Methods']='POST,OPTIONS'}
  return new Response(status===204?null:JSON.stringify(body),{status,headers});
}
function rng(seedInput:number){
  let seed=seedInput>>>0;if(!seed)seed=0x6d2b79f5;
  return ()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return (seed>>>0)/4294967296};
}
function checkNoughts(moves:number[]){
  if(!Array.isArray(moves)||moves.length<3||moves.length>9||moves.some(x=>!Number.isInteger(x)||x<0||x>8))throw new Error('Invalid Noughts move history.');
  const lines=[[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];
  const winner=(b:string[])=>{for(const line of lines)if(b[line[0]]&&b[line[0]]===b[line[1]]&&b[line[1]]===b[line[2]])return b[line[0]];return b.every(Boolean)?'draw':null};
  function evaluate(b:string[],maximizing:boolean,depth:number):number{
    const result=winner(b);if(result==='O')return 10-depth;if(result==='X')return depth-10;if(result==='draw')return 0;
    const vals:number[]=[];for(let i=0;i<9;i++)if(!b[i]){b[i]=maximizing?'O':'X';vals.push(evaluate(b,!maximizing,depth+1));b[i]=''}return maximizing?Math.max(...vals):Math.min(...vals);
  }
  const board=Array(9).fill('') as string[];let result:string|null=null;
  for(const move of moves){
    if(result||board[move])throw new Error('Invalid Noughts move.');
    board[move]='X';result=winner(board);if(result)break;
    let best=-Infinity,cpu=-1;
    for(let i=0;i<9;i++)if(!board[i]){board[i]='O';const value=evaluate(board,false,0);board[i]='';if(value>best){best=value;cpu=i}}
    if(cpu<0)throw new Error('Invalid Noughts game state.');
    board[cpu]='O';result=winner(board);
  }
  if(!result)throw new Error('Finish the Noughts round before submitting it.');
  return {score:result==='X'?1:0,progression:moves.length,won:result==='X'};
}
const ladders:Record<number,number>={3:22,8:30,20:41,28:74,50:67,71:91,80:99};
const snakes:Record<number,number>={17:7,54:34,62:19,64:60,87:36,93:73,95:75,98:79};
function checkLadders(seed:number,rollCount:number){
  if(!Number.isInteger(rollCount)||rollCount<1||rollCount>500)throw new Error('Invalid Snakes & Ladders run.');
  const random=rng(seed);let player=0,cpu=0,result:string|null=null;
  const move=(position:number)=>{let next=position+Math.ceil(random()*6);if(next>100)next=position;if(ladders[next])next=ladders[next];else if(snakes[next])next=snakes[next];return next};
  for(let i=0;i<rollCount;i++){
    player=move(player);if(player===100){result='player';if(i!==rollCount-1)throw new Error('Rolls continue after the match ended.');break;}
    cpu=move(cpu);if(cpu===100){result='cpu';if(i!==rollCount-1)throw new Error('Rolls continue after the match ended.');break;}
  }
  if(!result)throw new Error('Finish the Snakes & Ladders match before submitting it.');
  return {score:player,progression:rollCount,won:result==='player'};
}

const tetrisShapes:number[][][]=[
  [[1,1,1,1]],[[1,1],[1,1]],[[0,1,0],[1,1,1]],[[1,0,0],[1,1,1]],
  [[0,0,1],[1,1,1]],[[0,1,1],[1,1,0]],[[1,1,0],[0,1,1]]
];
function checkTetris(seed:number,placements:{shapeId:number;rotation:number;x:number}[]){
  if(!Array.isArray(placements)||placements.length<1||placements.length>500)throw new Error('Invalid Tetris placement history.');
  const random=rng(seed),grid=Array.from({length:20},()=>Array(10).fill(0));
  let lines=0,score=0,level=1,expected=Math.floor(random()*tetrisShapes.length),ended=false;
  const collides=(shape:number[][],x:number,y:number)=>shape.some((row,dy)=>row.some((cell,dx)=>!!cell&&(x+dx<0||x+dx>=10||y+dy>=20||(y+dy>=0&&grid[y+dy][x+dx]!==0))));
  const rotate=(shape:number[][])=>shape[0].map((_,i)=>shape.map(row=>row[i]).reverse());
  for(let index=0;index<placements.length;index++){
    const placement=placements[index];
    if(ended)throw new Error('Placements continue after the run ended.');
    if(!placement||placement.shapeId!==expected||!Number.isInteger(placement.rotation)||placement.rotation<0||placement.rotation>3||!Number.isInteger(placement.x)||placement.x<0||placement.x>9)throw new Error('Invalid Tetris placement.');
    let shape=tetrisShapes[expected].map(row=>[...row]);
    for(let r=0;r<placement.rotation;r++)shape=rotate(shape);
    if(collides(shape,placement.x,0))throw new Error('Invalid Tetris landing.');
    let y=0;while(!collides(shape,placement.x,y+1))y++;
    shape.forEach((row,dy)=>row.forEach((cell,dx)=>{if(cell)grid[y+dy][placement.x+dx]=expected+1}));
    let cleared=0;for(let row=grid.length-1;row>=0;row--){if(grid[row].every(Boolean)){grid.splice(row,1);grid.unshift(Array(10).fill(0));cleared++;row++}}
    if(cleared){lines+=cleared;score+=[0,100,300,500,800][cleared]*level;level=1+Math.floor(lines/10)}
    expected=Math.floor(random()*tetrisShapes.length);
    ended=collides(tetrisShapes[expected],3,0);
    if(ended&&index!==placements.length-1)throw new Error('Placements continue after the run ended.');
  }
  if(!ended)throw new Error('Finish the Tetris run before submitting it.');
  return {score,progression:level,won:false};
}

type CheckersMove={side:'r'|'b';fx:number;fy:number;tx:number;ty:number};
function checkCheckers(history:CheckersMove[]){
  if(!Array.isArray(history)||history.length<5||history.length>500)throw new Error('Invalid Checkers move history.');
  const board=(Array.from({length:8},()=>Array(8).fill(null)) as (string|null)[][]);
  for(let y=0;y<3;y++)for(let x=0;x<8;x++)if((x+y)%2===1)board[y][x]='b';
  for(let y=5;y<8;y++)for(let x=0;x<8;x++)if((x+y)%2===1)board[y][x]='r';
  const color=(piece:string|null)=>piece?.toLowerCase()||null;
  const movesFor=(side:'r'|'b',from?:{x:number;y:number})=>{
    const captures:CheckersMove[]=[],steps:CheckersMove[]=[];
    for(let y=0;y<8;y++)for(let x=0;x<8;x++){
      const piece=board[y][x];if(!piece||color(piece)!==side)continue;
      const dirs=piece===piece.toUpperCase()?[-1,1]:[side==='r'?-1:1];
      for(const dy of dirs)for(const dx of [-1,1]){
        const nx=x+dx,ny=y+dy,jx=x+dx*2,jy=y+dy*2;
        if(nx>=0&&nx<8&&ny>=0&&ny<8&&board[ny][nx]&&color(board[ny][nx])!==side&&jx>=0&&jx<8&&jy>=0&&jy<8&&!board[jy][jx])captures.push({side,fx:x,fy:y,tx:jx,ty:jy});
        if(nx>=0&&nx<8&&ny>=0&&ny<8&&!board[ny][nx])steps.push({side,fx:x,fy:y,tx:nx,ty:ny});
      }
    }
    const eligible=(list:CheckersMove[])=>from?list.filter(m=>m.fx===from.x&&m.fy===from.y):list;
    return captures.length?eligible(captures):eligible(steps);
  };
  let side:'r'|'b'='r',forced:{x:number;y:number}|null=null,winner:'r'|'b'|null=null,redCaptures=0;
  for(let index=0;index<history.length;index++){
    const move=history[index];
    if(winner||!move||move.side!==side||![move.fx,move.fy,move.tx,move.ty].every(Number.isInteger)||[move.fx,move.fy,move.tx,move.ty].some(n=>n<0||n>7))throw new Error('Invalid Checkers turn.');
    const legal=movesFor(side,forced||undefined),selected=legal.find(m=>m.fx===move.fx&&m.fy===move.fy&&m.tx===move.tx&&m.ty===move.ty);
    if(!selected)throw new Error('Illegal Checkers move.');
    const piece=board[move.fy][move.fx]!,mx=(move.fx+move.tx)/2,my=(move.fy+move.ty)/2,captured=Math.abs(move.tx-move.fx)===2;
    board[move.fy][move.fx]=null;
    if(captured){if(!board[my][mx]||color(board[my][mx])===side)throw new Error('Invalid Checkers capture.');board[my][mx]=null;if(side==='r')redCaptures++;}
    board[move.ty][move.tx]=piece;
    if((side==='r'&&move.ty===0)||(side==='b'&&move.ty===7))board[move.ty][move.tx]=side.toUpperCase();
    const count=board.flat().filter(p=>p&&color(p)===side).length;
    if(!count||!movesFor(side).length){winner=side==='r'?'b':'r';if(index!==history.length-1)throw new Error('Moves continue after the match ended.');break;}
    const follow=captured?movesFor(side,{x:move.tx,y:move.ty}).filter(m=>Math.abs(m.tx-m.fx)===2):[];
    if(follow.length){forced={x:move.tx,y:move.ty};continue;}
    forced=null;const opponent: 'r'|'b'=side==='r'?'b':'r';if(!board.flat().some(p=>p&&color(p)===opponent)||!movesFor(opponent).length){winner=side;if(index!==history.length-1)throw new Error('Moves continue after the match ended.');break;}side=opponent;
  }
  if(!winner)throw new Error('Finish the Checkers match before submitting it.');
  return {score:redCaptures,progression:history.length,won:winner==='r'};
}

type ChessMove={side:'w'|'b';fromX:number;fromY:number;toX:number;toY:number};
function checkChess(history:ChessMove[]){
  if(!Array.isArray(history)||history.length<4||history.length>500)throw new Error('Invalid Chess move history.');
  const board=(['rnbqkbnr','pppppppp','........','........','........','........','PPPPPPPP','RNBQKBNR'].map(row=>row.split('').map(p=>p==='.'?null:p)) as (string|null)[][]);
  let side:'w'|'b'='w',ep:{x:number;y:number}|null=null,castle={wK:true,wQ:true,bK:true,bQ:true},winner:'w'|'b'|'draw'|null=null;
  const color=(piece:string|null)=>piece?(piece===piece.toUpperCase()?'w':'b'):null,inside=(x:number,y:number)=>x>=0&&x<8&&y>=0&&y<8;
  const attacked=(x:number,y:number,by:'w'|'b')=>{
    for(let yy=0;yy<8;yy++)for(let xx=0;xx<8;xx++){
      const p=board[yy][xx];if(!p||color(p)!==by)continue;
      const dx=x-xx,dy=y-yy,t=p.toLowerCase();
      if(t==='p'&&Math.abs(dx)===1&&dy===(by==='w'?-1:1))return true;
      if(t==='n'&&Math.abs(dx)*Math.abs(dy)===2)return true;
      if(t==='k'&&Math.max(Math.abs(dx),Math.abs(dy))===1)return true;
      if(['b','r','q'].includes(t)){
        const diagonal=Math.abs(dx)===Math.abs(dy),straight=dx===0||dy===0;
        if((t==='b'&&!diagonal)||(t==='r'&&!straight)||(t==='q'&&!diagonal&&!straight))continue;
        const sx=Math.sign(dx),sy=Math.sign(dy);let cx=xx+sx,cy=yy+sy,blocked=false;
        while(cx!==x||cy!==y){if(board[cy][cx]){blocked=true;break}cx+=sx;cy+=sy}
        if(!blocked)return true;
      }
    }return false;
  };
  const inCheck=(which:'w'|'b')=>{const king=which==='w'?'K':'k';for(let y=0;y<8;y++)for(let x=0;x<8;x++)if(board[y][x]===king)return attacked(x,y,which==='w'?'b':'w');return true};
  const pseudo=(x:number,y:number)=>{
    const p=board[y][x],which=color(p) as 'w'|'b',t=p!.toLowerCase(),out:{x:number;y:number;double?:boolean;ep?:boolean;castle?:'K'|'Q'}[]=[];
    const add=(tx:number,ty:number,extra={})=>{if(inside(tx,ty)&&color(board[ty][tx])!==which)out.push({x:tx,y:ty,...extra})};
    if(t==='p'){
      const d=which==='w'?-1:1,start=which==='w'?6:1;
      if(inside(x,y+d)&&!board[y+d][x]){add(x,y+d);if(y===start&&!board[y+2*d][x])add(x,y+2*d,{double:true})}
      for(const dx of [-1,1]){if(inside(x+dx,y+d)&&color(board[y+d][x+dx])&&color(board[y+d][x+dx])!==which)add(x+dx,y+d);if(ep&&ep.x===x+dx&&ep.y===y+d)out.push({x:x+dx,y:y+d,ep:true})}
    }else if(t==='n'){[[1,2],[2,1],[-1,2],[-2,1],[1,-2],[2,-1],[-1,-2],[-2,-1]].forEach(([dx,dy])=>add(x+dx,y+dy))}
    else if(t==='k'){
      for(let dx=-1;dx<=1;dx++)for(let dy=-1;dy<=1;dy++)if(dx||dy)add(x+dx,y+dy);
      const row=which==='w'?7:0,opp=which==='w'?'b':'w';
      if(y===row&&x===4&&!inCheck(which)){
        for(const wing of ['K','Q'] as const)if(castle[which+wing]){
          const spaces=wing==='K'?[5,6]:[1,2,3],through=wing==='K'?[5,6]:[3,2];
          if(spaces.every(cx=>!board[row][cx])&&through.every(cx=>!attacked(cx,row,opp)))out.push({x:wing==='K'?6:2,y:row,castle:wing});
        }
      }
    }else{
      const dirs:number[][]=[];if(t==='b'||t==='q')dirs.push([1,1],[1,-1],[-1,1],[-1,-1]);if(t==='r'||t==='q')dirs.push([1,0],[-1,0],[0,1],[0,-1]);
      for(const [dx,dy] of dirs){let tx=x+dx,ty=y+dy;while(inside(tx,ty)){if(color(board[ty][tx])===which)break;out.push({x:tx,y:ty});if(board[ty][tx])break;tx+=dx;ty+=dy}}
    }return out;
  };
  const apply=(fx:number,fy:number,m:{x:number;y:number;double?:boolean;ep?:boolean;castle?:'K'|'Q'})=>{
    const moving=board[fy][fx];board[fy][fx]=null;
    if(m.ep)board[fy+(color(moving)==='w'?1:-1)][m.x]=null;
    if(m.castle){const row=fy;if(m.castle==='K'){board[row][5]=board[row][7];board[row][7]=null}else{board[row][3]=board[row][0];board[row][0]=null}}
    board[m.y][m.x]=(moving!.toLowerCase()==='p'&&(m.y===0||m.y===7))?(color(moving)==='w'?'Q':'q'):moving;
    ep=m.double?{x:fx,y:fy+(color(moving)==='w'?-1:1)}:null;
    if(moving==='K'){castle.wK=castle.wQ=false}if(moving==='k'){castle.bK=castle.bQ=false}
    if(moving==='R'&&fx===0&&fy===7)castle.wQ=false;if(moving==='R'&&fx===7&&fy===7)castle.wK=false;if(moving==='r'&&fx===0&&fy===0)castle.bQ=false;if(moving==='r'&&fx===7&&fy===0)castle.bK=false;
    if(m.x===0&&m.y===7)castle.wQ=false;if(m.x===7&&m.y===7)castle.wK=false;if(m.x===0&&m.y===0)castle.bQ=false;if(m.x===7&&m.y===0)castle.bK=false;
  };
  const legal=(x:number,y:number)=>{
    const piece=board[y][x],which=color(piece) as 'w'|'b';return pseudo(x,y).filter(move=>{
      const snap=board.map(row=>row.slice()),ep0=ep,castle0={...castle};apply(x,y,move);const safe=!inCheck(which);
      for(let i=0;i<8;i++)board[i]=snap[i];ep=ep0;castle=castle0;return safe;
    });
  };
  const allMoves=(which:'w'|'b')=>{const out:{x:number;y:number;m:{x:number;y:number;double?:boolean;ep?:boolean;castle?:'K'|'Q'}}[]=[];for(let y=0;y<8;y++)for(let x=0;x<8;x++)if(color(board[y][x])===which)for(const m of legal(x,y))out.push({x,y,m});return out};
  for(let index=0;index<history.length;index++){
    const move=history[index];
    if(winner||!move||move.side!==side||![move.fromX,move.fromY,move.toX,move.toY].every(Number.isInteger)||[move.fromX,move.fromY,move.toX,move.toY].some(n=>n<0||n>7)||color(board[move.fromY]?.[move.fromX])!==side)throw new Error('Invalid Chess turn.');
    const selected=legal(move.fromX,move.fromY).find(m=>m.x===move.toX&&m.y===move.toY);
    if(!selected)throw new Error('Illegal Chess move.');
    apply(move.fromX,move.fromY,selected);side=side==='w'?'b':'w';
    const options=allMoves(side);
    if(!options.length){winner=inCheck(side)?(side==='w'?'b':'w'):'draw';if(index!==history.length-1)throw new Error('Moves continue after the Chess game ended.');break;}
  }
  if(!winner)throw new Error('Finish the Chess game before submitting it.');
  return {score:winner==='w'?1:0,progression:history.length,won:winner==='w'};
}

Deno.serve(async(request)=>{
  const origin=request.headers.get('origin');
  if(origin&&!allowedOrigins.has(origin))return respond({error:'Origin not allowed.'},403,null);
  if(request.method==='OPTIONS')return respond({},204,origin);
  if(request.method!=='POST')return respond({error:'POST required.'},405,origin);
  const token=request.headers.get('authorization')?.replace(/^Bearer\s+/i,'');
  if(!token)return respond({error:'Sign in to save arcade scores and XP.'},401,origin);
  const {data:authData,error:authError}=await userClient.auth.getUser(token);
  if(authError||!authData.user)return respond({error:'Your session could not be verified. Sign in again.'},401,origin);
  try{
    const body=await request.json(),gameKey=body.gameKey;
    if(!['noughts','ladders','tetris','checkers','chess'].includes(gameKey))return respond({error:'This game is not enabled for verified results yet.'},400,origin);
    if(body.action==='start'){
      const {count,error:countError}=await admin.from('verified_arcade_runs').select('id',{count:'exact',head:true})
        .eq('user_id',authData.user.id).gt('started_at',new Date(Date.now()-60_000).toISOString());
      if(countError)throw countError;
      if((count||0)>=10)return respond({error:'Please wait a minute before starting another run.'},429,origin);
      const bytes=new Uint32Array(1);crypto.getRandomValues(bytes);const seed=bytes[0]||0x6d2b79f5;
      const {data,error}=await admin.from('verified_arcade_runs').insert({user_id:authData.user.id,game_key:gameKey,seed}).select('id').single();
      if(error)throw error;
      return respond({runId:data.id,seed},200,origin);
    }
    if(body.action!=='finish'||typeof body.runId!=='string')return respond({error:'Invalid arcade request.'},400,origin);
    const {data:run,error:runError}=await admin.from('verified_arcade_runs').select('id,user_id,game_key,seed,finished_at,score').eq('id',body.runId).maybeSingle();
    if(runError)throw runError;
    if(!run||run.user_id!==authData.user.id||run.game_key!==gameKey)return respond({error:'Arcade run not found.'},404,origin);
    if(run.finished_at)return respond({score:run.score,xp_reward:0,already_counted:true},200,origin);
    const result=gameKey==='noughts'?checkNoughts(body.moves):gameKey==='ladders'?checkLadders(Number(run.seed),Number(body.rollCount)):gameKey==='tetris'?checkTetris(Number(run.seed),body.placements):gameKey==='checkers'?checkCheckers(body.moves):checkChess(body.moves);
    const {data,error}=await admin.rpc('record_verified_board_run',{p_run_id:run.id,p_game_key:gameKey,p_score:result.score,p_progression_count:result.progression,p_won:result.won});
    if(error)throw error;
    return respond(data,200,origin);
  }catch(error){
    console.error('Verified board result rejected:',error);
    const message=error instanceof Error&&/Invalid|Finish|Rolls continue|Complete/.test(error.message)?error.message:'The game result could not be saved. No XP was awarded.';
    return respond({error:message},400,origin);
  }
});
