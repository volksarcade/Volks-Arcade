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
    if(!['noughts','ladders','tetris'].includes(gameKey))return respond({error:'This game is not enabled for verified results yet.'},400,origin);
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
    const result=gameKey==='noughts'?checkNoughts(body.moves):gameKey==='ladders'?checkLadders(Number(run.seed),Number(body.rollCount)):checkTetris(Number(run.seed),body.placements);
    const {data,error}=await admin.rpc('record_verified_board_run',{p_run_id:run.id,p_game_key:gameKey,p_score:result.score,p_progression_count:result.progression,p_won:result.won});
    if(error)throw error;
    return respond(data,200,origin);
  }catch(error){
    console.error('Verified board result rejected:',error);
    const message=error instanceof Error&&/Invalid|Finish|Rolls continue|Complete/.test(error.message)?error.message:'The game result could not be saved. No XP was awarded.';
    return respond({error:message},400,origin);
  }
});
