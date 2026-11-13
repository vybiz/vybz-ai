// Supabase Edge Function named "vybz". Secrets: GROQ_API_KEY or GEMINI_API_KEY (one is enough), YOUTUBE_API_KEY. Also OPENROUTER_API_KEY. Optional: GROQ_MODEL, OPENROUTER_MODEL, GEMINI_MODEL.
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const clip=(v:unknown,n:number)=>String(v??"").slice(0,n);

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  try{
    const b=await req.json();
    if(b.action==="write"){
      const key=Deno.env.get("GEMINI_API_KEY"),gk=Deno.env.get("GROQ_API_KEY"),ok=Deno.env.get("OPENROUTER_API_KEY");if(!key&&!gk&&!ok)return json({error:"Set GROQ_API_KEY, OPENROUTER_API_KEY or GEMINI_API_KEY as a secret"},500);
      const model=Deno.env.get("GEMINI_MODEL")||"gemini-2.0-flash";
      const lang=clip(b.language,60)||"English",genre=clip(b.genre,60)||"whatever genre fits",mood=clip(b.mood,60)||"any",
            topic=clip(b.topic,300),dir=clip(b.direction,300);
      const rules="Write 100% original lyrics. Never reproduce or paraphrase lyrics, titles or melodies of existing songs and never imitate a named artist. Use hit-friendly craft: a hook in the first lines, a 1-2 line chorus that repeats, simple quotable words, one clear emotion, a twist in the last line. Keep lines singable and label sections.";
      const task=b.mode==="hooks"
        ?`Write 5 different original 15-second hook ideas (2-4 short lines each) about: ${topic}. Genre: ${genre}. Language: ${lang}. Mood: ${mood}. ${dir}`
        :b.mode==="rhymes"
        ?`List 20 rhyming and near-rhyming words for "${clip(b.topic,40)}" in ${lang}, grouped by syllable count.`
        :`Write a complete song (verse 1, pre-chorus, chorus, verse 2, bridge, final chorus) about: ${topic}. Genre: ${genre}. Language: ${lang} (mix languages if asked). Mood: ${mood}. ${dir} End with a caption and 5 hashtags.`;
      if(!gk&&ok){const orr=await fetch("https://openrouter.ai/api/v1/chat/completions",{method:"POST",headers:{"Content-Type":"application/json",Authorization:`Bearer ${ok}`},
        body:JSON.stringify({model:Deno.env.get("OPENROUTER_MODEL")||"meta-llama/llama-3.3-70b-instruct:free",messages:[{role:"system",content:rules},{role:"user",content:task}],temperature:1})});
        const od=await orr.json();if(!orr.ok)return json({error:od?.error?.message||"OpenRouter error"},502);return json({text:od?.choices?.[0]?.message?.content||""});}
      if(gk){const gr=await fetch("https://api.groq.com/openai/v1/chat/completions",{method:"POST",headers:{"Content-Type":"application/json",Authorization:`Bearer ${gk}`},
        body:JSON.stringify({model:Deno.env.get("GROQ_MODEL")||"openai/gpt-oss-120b",messages:[{role:"system",content:rules},{role:"user",content:task}],temperature:1})});
        const gd=await gr.json();if(!gr.ok)return json({error:gd?.error?.message||"Groq error"},502);return json({text:gd?.choices?.[0]?.message?.content||""});}
      const r=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,{
        method:"POST",headers:{"Content-Type":"application/json"},
        body:JSON.stringify({systemInstruction:{parts:[{text:rules}]},contents:[{parts:[{text:task}]}],generationConfig:{temperature:1}})});
      const d=await r.json();
      if(!r.ok)return json({error:d?.error?.message||"AI provider error"},502);
      return json({text:d?.candidates?.[0]?.content?.parts?.[0]?.text||""});
    }
    if(b.action==="trends"){
      const key=Deno.env.get("YOUTUBE_API_KEY");if(!key)return json({error:"YOUTUBE_API_KEY secret is not set"},500);
      const region=/^[A-Z]{2}$/.test(b.region)?b.region:"US";
      const r=await fetch(`https://www.googleapis.com/youtube/v3/videos?part=snippet,statistics&chart=mostPopular&videoCategoryId=10&regionCode=${region}&maxResults=30&key=${key}`);
      const d=await r.json();
      if(!r.ok)return json({error:d?.error?.message||"YouTube error"},502);
      return json({region,fetchedAt:new Date().toISOString(),items:(d.items||[]).map((v:any)=>({id:v.id,title:v.snippet?.title,channel:v.snippet?.channelTitle,
        publishedAt:v.snippet?.publishedAt,views:+v.statistics?.viewCount||0,likes:+v.statistics?.likeCount||0}))});
    }
    return json({error:"Unknown action"},400);
  }catch(e){return json({error:String(e)},500);}
});
