// codetunner-native/microrent-ai-proxy/supabase/functions/ai-proxy/index.ts
// Supabase Edge Function implementation for MicroRent AI Proxy

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.14.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized. Missing Authorization header." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Initialize Supabase Auth Check
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );

    // 1. Verify User Authentication
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized. Invalid Token." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Extract Request payload
    const bodyText = await req.text();
    let bodyObj;
    try { bodyObj = JSON.parse(bodyText); } catch { bodyObj = {}; }

    // Read routing info from headers instead of the body
    const provider = req.headers.get("x-microrent-provider");
    const model = req.headers.get("x-microrent-model") || bodyObj?.model;
    const isStream = req.headers.get("x-microrent-stream") === "true";

    if (!provider || !model) {
        return new Response(JSON.stringify({ error: "Missing x-microrent-provider or x-microrent-model headers." }), {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }

    // 3. Fetch User Subscription and AI Usage Quota
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );
      
    const { data: profile, error: profileErr } = await supabaseAdmin
      .from('profiles')
      .select('subscription_plan, ai_monthly_tokens_used, free_tokens_remaining')
      .eq('id', user.id)
      .single();

    if (profileErr || !profile) {
      return new Response(JSON.stringify({ error: "Profile not found or quota cannot be verified." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { subscription_plan, free_tokens_remaining } = profile;

    // Strict Free Plan Policy
    if (subscription_plan === "free" && free_tokens_remaining <= 0) {
      return new Response(JSON.stringify({ error: "Token quota exceeded on Free plan." }), {
        status: 402, // Payment Required
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Model Validation
    const premiumModels = ["gpt-4o", "claude-3-5-sonnet-20241022", "gemini-1.5-pro", "claude-3-opus-20240229"];
    if (subscription_plan === "free" && premiumModels.includes(model)) {
      return new Response(JSON.stringify({ error: "Premium models require a Pro or Enterprise subscription." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 4. Proxy the Request based on Provider
    let proxyResponse: Response;
    
    if (provider === "openai") {
      const apiKey = Deno.env.get("OPENAI_API_KEY");
      proxyResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: bodyText, // Pass through verbatim
      });
    } 
    else if (provider === "anthropic") {
      const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
      proxyResponse = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": apiKey!,
          "anthropic-version": "2023-06-01",
          "Content-Type": "application/json",
        },
        body: bodyText, // Pass through verbatim
      });
    } 
    else if (provider === "gemini") {
      const apiKey = Deno.env.get("GEMINI_API_KEY");
      const url = isStream 
        ? `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?key=${apiKey}`
        : `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
        
      proxyResponse = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: bodyText, // Pass through verbatim
      });
    } else {
      return new Response(JSON.stringify({ error: "Unsupported AI provider." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!proxyResponse.ok) {
        const errText = await proxyResponse.text();
        return new Response(JSON.stringify({ error: "Provider Error", details: errText }), {
            status: proxyResponse.status,
            headers: { ...corsHeaders, "Content-Type": "application/json" }
        });
    }

    // 5. Stream the response directly back to the client
    if (isStream && proxyResponse.body) {
      let tokenEstimate = 0;
      
      const { readable, writable } = new TransformStream({
        transform(chunk, controller) {
          controller.enqueue(chunk);
          // Very rough token estimate for demonstration: 1 token ~ 4 chars of output bytechunk
          tokenEstimate += Math.ceil(chunk.byteLength / 4);
        },
        async flush() {
          // Asynchronously deduct token usage from user profile
          if (subscription_plan === "free") {
            await supabaseAdmin.rpc('deduct_free_tokens', { 
               user_uuid: user.id, 
               amount: tokenEstimate 
            });
          } else {
             await supabaseAdmin.rpc('increment_used_tokens', { 
               user_uuid: user.id, 
               amount: tokenEstimate 
            });
          }
        }
      });
      
      // Pipe response from AI provider to our writable stream
      proxyResponse.body.pipeTo(writable);

      return new Response(readable, {
        headers: { ...corsHeaders, "Content-Type": "text/event-stream" }
      });
    }

    // For non-streaming requests
    const resData = await proxyResponse.json();
    
    // Asynchronously deduct 
    let usage = 100; // Fallback
    if (provider === "openai" && resData.usage) {
        usage = resData.usage.total_tokens;
    } else if (provider === "anthropic" && resData.usage) {
        usage = resData.usage.input_tokens + resData.usage.output_tokens;
    }
    
    if (subscription_plan === "free") {
        supabaseAdmin.rpc('deduct_free_tokens', { user_uuid: user.id, amount: usage }).then().catch(console.error);
    } else {
        supabaseAdmin.rpc('increment_used_tokens', { user_uuid: user.id, amount: usage }).then().catch(console.error);
    }

    return new Response(JSON.stringify(resData), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
    
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
