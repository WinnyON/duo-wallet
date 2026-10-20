import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface FrankfurterResponse {
  amount: number;
  base: string;
  date: string;
  rates: {
    HUF: number;
    RON: number;
  };
}

Deno.serve(async () => {
  try {
    const res = await fetch('https://api.frankfurter.app/latest?from=EUR&to=HUF,RON');
    if (!res.ok) {
      return new Response(JSON.stringify({ error: `ECB fetch failed: ${res.status}` }), {
        status: 502,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const data = (await res.json()) as FrankfurterResponse;
    const rateDate = data.date;
    const eurToHuf = Number(data.rates.HUF);
    const eurToRon = Number(data.rates.RON);

    if (!rateDate || !Number.isFinite(eurToHuf) || !Number.isFinite(eurToRon) || eurToHuf <= 0 || eurToRon <= 0) {
      return new Response(JSON.stringify({ error: 'Invalid FX payload from frankfurter.app' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const ronToHuf = eurToHuf / eurToRon;
    const rows = [
      { rate_date: rateDate, base: 'HUF', quote: 'HUF', rate: 1 },
      { rate_date: rateDate, base: 'EUR', quote: 'EUR', rate: 1 },
      { rate_date: rateDate, base: 'RON', quote: 'RON', rate: 1 },
      { rate_date: rateDate, base: 'EUR', quote: 'HUF', rate: Number(eurToHuf.toFixed(8)) },
      { rate_date: rateDate, base: 'HUF', quote: 'EUR', rate: Number((1 / eurToHuf).toFixed(8)) },
      { rate_date: rateDate, base: 'EUR', quote: 'RON', rate: Number(eurToRon.toFixed(8)) },
      { rate_date: rateDate, base: 'RON', quote: 'EUR', rate: Number((1 / eurToRon).toFixed(8)) },
      { rate_date: rateDate, base: 'RON', quote: 'HUF', rate: Number(ronToHuf.toFixed(8)) },
      { rate_date: rateDate, base: 'HUF', quote: 'RON', rate: Number((1 / ronToHuf).toFixed(8)) },
    ];

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { error } = await supabase
      .from('fx_rates')
      .upsert(rows, { onConflict: 'rate_date,base,quote' });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true, date: rateDate, count: rows.length }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
