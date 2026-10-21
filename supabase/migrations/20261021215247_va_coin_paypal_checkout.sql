create table public.va_coin_orders (
  paypal_order_id text primary key check (char_length(paypal_order_id) between 1 and 128),
  user_id uuid not null references auth.users(id) on delete cascade,
  package_key text not null check (package_key in ('starter', 'popular', 'bundle')),
  coin_amount bigint not null,
  amount_pence integer not null,
  currency text not null default 'GBP' check (currency = 'GBP'),
  status text not null default 'created' check (status in ('created', 'completed')),
  capture_id text unique,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint va_coin_order_package_amount check (
    (package_key = 'starter' and coin_amount = 100 and amount_pence = 99)
    or (package_key = 'popular' and coin_amount = 550 and amount_pence = 499)
    or (package_key = 'bundle' and coin_amount = 1200 and amount_pence = 999)
  ),
  constraint va_coin_order_capture_state check (
    (status = 'created' and capture_id is null and completed_at is null)
    or (status = 'completed' and capture_id is not null and completed_at is not null)
  )
);

alter table public.va_coin_orders enable row level security;
revoke all on table public.va_coin_orders from public, anon, authenticated;
grant select, insert, update on table public.va_coin_orders to service_role;

create index va_coin_orders_user_created_idx
  on public.va_coin_orders (user_id, created_at desc);

create or replace function public.fulfill_va_coin_order(
  p_order_id text,
  p_capture_id text,
  p_user_id uuid,
  p_package_key text,
  p_amount_pence integer,
  p_currency text,
  p_custom_id text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  order_row public.va_coin_orders%rowtype;
  balance_after bigint;
begin
  if p_order_id is null or p_capture_id is null or p_user_id is null then
    raise exception 'Invalid VA Coin payment reference';
  end if;

  select * into order_row
  from public.va_coin_orders
  where paypal_order_id = p_order_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'Payment order not found';
  end if;

  if order_row.status = 'completed' then
    select va_coins into balance_after from public.xp_wallets where user_id = p_user_id;
    return jsonb_build_object('already_fulfilled', true, 'coin_amount', order_row.coin_amount, 'va_coins', coalesce(balance_after, 0));
  end if;

  if order_row.package_key <> p_package_key
     or order_row.amount_pence <> p_amount_pence
     or order_row.currency <> p_currency
     or p_currency <> 'GBP'
     or p_custom_id <> p_user_id::text then
    raise exception 'Payment does not match the VA Coin order';
  end if;

  update public.xp_wallets
    set va_coins = va_coins + order_row.coin_amount,
        updated_at = now()
    where user_id = p_user_id
    returning va_coins into balance_after;

  if not found then
    raise exception 'Player wallet not found';
  end if;

  insert into public.store_coin_ledger(user_id, amount, source, reference_id)
    values (p_user_id, order_row.coin_amount, 'paypal-purchase', p_order_id);

  update public.va_coin_orders
    set status = 'completed', capture_id = p_capture_id, completed_at = now()
    where paypal_order_id = p_order_id;

  return jsonb_build_object('already_fulfilled', false, 'coin_amount', order_row.coin_amount, 'va_coins', balance_after);
end;
$function$;

revoke all on function public.fulfill_va_coin_order(text, text, uuid, text, integer, text, text) from public, anon, authenticated;
grant execute on function public.fulfill_va_coin_order(text, text, uuid, text, integer, text, text) to service_role;
