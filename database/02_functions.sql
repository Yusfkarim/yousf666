-- Trusted server-side marketplace logic.
-- Run after schema.sql and before rls.sql. Every callable function has a fixed search_path.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

create or replace function public.guard_order_financial_snapshots()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if row(
    new.id, new.order_number, new.buyer_id, new.store_id, new.payment_method,
    new.subtotal_iqd, new.delivery_fee_iqd, new.total_iqd,
    new.commission_type_snapshot, new.commission_value_snapshot,
    new.commission_amount_iqd, new.store_net_payout_iqd,
    new.delivery_lat, new.delivery_lng, new.delivery_address,
    new.buyer_note, new.buyer_phone_snapshot, new.created_at
  ) is distinct from row(
    old.id, old.order_number, old.buyer_id, old.store_id, old.payment_method,
    old.subtotal_iqd, old.delivery_fee_iqd, old.total_iqd,
    old.commission_type_snapshot, old.commission_value_snapshot,
    old.commission_amount_iqd, old.store_net_payout_iqd,
    old.delivery_lat, old.delivery_lng, old.delivery_address,
    old.buyer_note, old.buyer_phone_snapshot, old.created_at
  ) then
    raise exception 'Order financial and delivery snapshots are immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_guard_financial_snapshots on public.orders;
create trigger orders_guard_financial_snapshots
before update on public.orders
for each row execute function public.guard_order_financial_snapshots();

create or replace function public.guard_order_item_snapshots()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if row(
    new.id, new.order_id, new.product_name_snapshot, new.unit_price_iqd, new.quantity, new.line_total_iqd
  ) is distinct from row(
    old.id, old.order_id, old.product_name_snapshot, old.unit_price_iqd, old.quantity, old.line_total_iqd
  ) or (new.product_id is distinct from old.product_id and new.product_id is not null) then
    raise exception 'Order item price and quantity snapshots are immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists order_items_guard_snapshots on public.order_items;
create trigger order_items_guard_snapshots
before update on public.order_items
for each row execute function public.guard_order_item_snapshots();

create or replace function public.guard_settlement_append_only()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  raise exception 'Settlement ledger rows are append-only';
end;
$$;

drop trigger if exists settlements_append_only on public.settlements;
create trigger settlements_append_only
before update or delete on public.settlements
for each row execute function public.guard_settlement_append_only();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, role, is_active)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), split_part(coalesce(new.email, ''), '@', 1)),
    'buyer',
    true
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- RLS helper functions are SECURITY DEFINER to avoid recursive profile/order policies.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin' and p.is_active
  );
$$;

create or replace function public.owns_store(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select exists (
    select 1
    from public.stores s
    join public.profiles p on p.id = s.owner_id and p.is_active and p.role in ('buyer', 'seller')
    where s.id = p_store_id and s.owner_id = auth.uid()
  );
$$;

create or replace function public.can_access_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select exists (
    select 1
    from public.orders o
    join public.stores s on s.id = o.store_id
    join public.profiles active_profile on active_profile.id = auth.uid() and active_profile.is_active
    where o.id = p_order_id
      and (
        o.buyer_id = auth.uid()
        or (o.driver_id = auth.uid() and active_profile.role = 'driver')
        or (s.owner_id = auth.uid() and active_profile.role = 'seller')
        or public.is_admin()
      )
  );
$$;

-- A profile may never choose its own role or active state. New accounts are buyers by default.
create or replace function public.current_profile_role()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select p.role from public.profiles p where p.id = auth.uid() and p.is_active;
$$;

-- Expose financial rollups only to the store owner and admins. SECURITY INVOKER keeps
-- the underlying delivered orders and settlement rows subject to their table RLS policies.
create or replace view public.store_financial_summary
with (security_invoker = true)
as
with delivered as (
  select store_id,
         count(*)::bigint as total_delivered_orders,
         coalesce(sum(subtotal_iqd), 0)::bigint as gross_sales_iqd,
         coalesce(sum(commission_amount_iqd), 0)::bigint as total_commission_iqd
  from public.orders
  where status = 'delivered'
  group by store_id
), paid as (
  select store_id,
         coalesce(sum(case direction
           when 'store_paid_platform' then amount_iqd
           else -amount_iqd
         end), 0)::bigint as total_settled_iqd
  from public.settlements
  group by store_id
)
select s.id as store_id,
       s.name as store_name,
       coalesce(d.total_delivered_orders, 0)::bigint as total_delivered_orders,
       coalesce(d.gross_sales_iqd, 0)::bigint as gross_sales_iqd,
       coalesce(d.total_commission_iqd, 0)::bigint as total_commission_iqd,
       coalesce(p.total_settled_iqd, 0)::bigint as total_settled_iqd,
       (coalesce(d.total_commission_iqd, 0) - coalesce(p.total_settled_iqd, 0))::bigint as current_balance_due_iqd
from public.stores s
left join delivered d on d.store_id = s.id
left join paid p on p.store_id = s.id
where public.owns_store(s.id) or public.is_admin();

create or replace function public.get_store_commission_settings(p_store_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_settings jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if not public.is_admin() and not public.owns_store(p_store_id) then
    raise exception 'Only the store owner or an admin may view its commission settings' using errcode = '42501';
  end if;
  select jsonb_build_object('commission_type', s.commission_type, 'commission_value', s.commission_value)
  into v_settings
  from public.stores s
  where s.id = p_store_id;
  if v_settings is null then raise exception 'Store not found'; end if;
  return v_settings;
end;
$$;

create or replace function public.admin_list_stores()
returns table(
  id uuid,
  name text,
  city text,
  is_approved boolean,
  is_open boolean,
  commission_type text,
  commission_value numeric,
  delivery_mode text,
  delivery_fee_iqd integer,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin access required' using errcode = '42501'; end if;
  return query
  select s.id, s.name, s.city, s.is_approved, s.is_open,
         s.commission_type, s.commission_value, s.delivery_mode, s.delivery_fee_iqd, s.created_at
  from public.stores s
  order by s.created_at desc;
end;
$$;

create or replace function public.quote_order(p_store_id uuid, p_items_json jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_store public.stores%rowtype;
  v_product public.products%rowtype;
  v_item record;
  v_element jsonb;
  v_subtotal bigint := 0;
  v_total bigint;
  v_items_count integer;
  v_units integer := 0;
begin
  if v_uid is null then raise exception 'Sign in before requesting an order quote' using errcode = '28000'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.is_active) then
    raise exception 'Your account is inactive';
  end if;
  if p_items_json is null or jsonb_typeof(p_items_json) <> 'array' then
    raise exception 'Order items must be a JSON array';
  end if;
  v_items_count := jsonb_array_length(p_items_json);
  if v_items_count < 1 or v_items_count > 50 then
    raise exception 'An order must contain between 1 and 50 different products';
  end if;
  for v_element in select value from jsonb_array_elements(p_items_json) as e(value)
  loop
    if jsonb_typeof(v_element) <> 'object'
       or coalesce(v_element ->> 'product_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or jsonb_typeof(v_element -> 'quantity') <> 'number'
       or coalesce(v_element ->> 'quantity', '') !~ '^[1-9][0-9]*$'
       or (v_element ->> 'quantity')::numeric > 99 then
      raise exception 'Each item requires a valid product_id and quantity from 1 to 99';
    end if;
  end loop;
  if (select count(distinct (e.value ->> 'product_id')::uuid)
      from jsonb_array_elements(p_items_json) as e(value)) <> v_items_count then
    raise exception 'Duplicate products are not allowed; combine their quantities';
  end if;

  select * into v_store from public.stores s where s.id = p_store_id for share;
  if not found or not v_store.is_approved or not v_store.is_open then
    raise exception 'This store is unavailable or closed';
  end if;

  for v_item in
    select (e.value ->> 'product_id')::uuid as product_id,
           (e.value ->> 'quantity')::integer as quantity
    from jsonb_array_elements(p_items_json) as e(value)
    order by (e.value ->> 'product_id')::uuid
  loop
    select * into v_product from public.products p where p.id = v_item.product_id for share;
    if not found or v_product.store_id <> p_store_id or not v_product.is_available then
      raise exception 'A product is no longer available from this store';
    end if;
    v_subtotal := v_subtotal + v_product.price_iqd::bigint * v_item.quantity::bigint;
    v_units := v_units + v_item.quantity;
    if v_subtotal > 2147483647 then raise exception 'Order subtotal exceeds the supported IQD limit'; end if;
  end loop;

  v_total := v_subtotal + v_store.delivery_fee_iqd::bigint;
  if v_total > 2147483647 then raise exception 'Order total exceeds the supported IQD limit'; end if;
  return jsonb_build_object(
    'subtotal_iqd', v_subtotal::integer,
    'delivery_fee_iqd', v_store.delivery_fee_iqd,
    'total_iqd', v_total::integer,
    'item_count', v_units
  );
end;
$$;

create or replace function public.create_order(
  p_store_id uuid,
  p_items_json jsonb,
  p_lat double precision,
  p_lng double precision,
  p_address text,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_store public.stores%rowtype;
  v_product public.products%rowtype;
  v_item record;
  v_element jsonb;
  v_phone text;
  v_order_id uuid;
  v_order_number bigint;
  v_subtotal bigint := 0;
  v_commission integer;
  v_total bigint;
  v_commission_calc numeric;
  v_qty integer;
  v_items_count integer;
begin
  if v_uid is null then
    raise exception 'Sign in before placing an order' using errcode = '28000';
  end if;
  if p_items_json is null or jsonb_typeof(p_items_json) <> 'array' then
    raise exception 'Order items must be a JSON array';
  end if;
  v_items_count := jsonb_array_length(p_items_json);
  if v_items_count < 1 or v_items_count > 50 then
    raise exception 'An order must contain between 1 and 50 different products';
  end if;

  -- Validate the payload before casting anything from JSON.
  for v_element in select value from jsonb_array_elements(p_items_json) as e(value)
  loop
    if jsonb_typeof(v_element) <> 'object'
       or coalesce(v_element ->> 'product_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or jsonb_typeof(v_element -> 'quantity') <> 'number'
       or coalesce(v_element ->> 'quantity', '') !~ '^[1-9][0-9]*$'
       or (v_element ->> 'quantity')::numeric > 99 then
      raise exception 'Each item requires a valid product_id and quantity from 1 to 99';
    end if;
  end loop;
  if (select count(distinct (e.value ->> 'product_id')::uuid)
      from jsonb_array_elements(p_items_json) as e(value)) <> v_items_count then
    raise exception 'Duplicate products are not allowed; combine their quantities';
  end if;

  select * into v_store
  from public.stores s
  where s.id = p_store_id
  for share;
  if not found or not v_store.is_approved or not v_store.is_open then
    raise exception 'This store is unavailable or closed';
  end if;

  select p.phone into v_phone
  from public.profiles p
  where p.id = v_uid and p.is_active;
  if not found then
    raise exception 'Your account is inactive';
  end if;
  if v_phone is null or v_phone !~ '^07[0-9]{9}$' then
    raise exception 'Add a valid Iraqi mobile number (07xxxxxxxxx) to your profile first';
  end if;
  if p_address is null or length(btrim(p_address)) = 0 or length(p_address) > 500 then
    raise exception 'A delivery address or landmark is required';
  end if;
  if length(coalesce(p_note, '')) > 500 then
    raise exception 'The order note is too long';
  end if;
  if (p_lat is null) <> (p_lng is null)
     or (p_lat is not null and (p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180)) then
    raise exception 'Invalid delivery coordinates';
  end if;

  -- Lock each authoritative product row and calculate only from database prices.
  for v_item in
    select (e.value ->> 'product_id')::uuid as product_id,
           (e.value ->> 'quantity')::integer as quantity
    from jsonb_array_elements(p_items_json) as e(value)
    order by (e.value ->> 'product_id')::uuid
  loop
    select * into v_product
    from public.products p
    where p.id = v_item.product_id
    for share;
    if not found or v_product.store_id <> p_store_id or not v_product.is_available then
      raise exception 'A product is no longer available from this store';
    end if;
    v_qty := v_item.quantity;
    v_subtotal := v_subtotal + (v_product.price_iqd::bigint * v_qty::bigint);
    if v_subtotal > 2147483647 then
      raise exception 'Order subtotal exceeds the supported IQD limit';
    end if;
  end loop;

  v_total := v_subtotal + v_store.delivery_fee_iqd::bigint;
  if v_total > 2147483647 then
    raise exception 'Order total exceeds the supported IQD limit';
  end if;

  if v_store.commission_type = 'percentage' then
    v_commission_calc := round(v_subtotal::numeric * v_store.commission_value / 100.0);
  else
    v_commission_calc := round(v_store.commission_value);
  end if;
  -- A store commission can never create a negative payout.
  v_commission := least(v_subtotal::numeric, greatest(0, v_commission_calc))::integer;

  insert into public.orders (
    buyer_id, store_id, status, payment_method,
    subtotal_iqd, delivery_fee_iqd, total_iqd,
    commission_type_snapshot, commission_value_snapshot,
    commission_amount_iqd, store_net_payout_iqd,
    delivery_lat, delivery_lng, delivery_address, buyer_note,
    buyer_phone_snapshot
  ) values (
    v_uid, p_store_id, 'pending', 'cod',
    v_subtotal::integer, v_store.delivery_fee_iqd, v_total::integer,
    v_store.commission_type, v_store.commission_value,
    v_commission, v_subtotal::integer - v_commission,
    p_lat, p_lng, btrim(p_address), coalesce(btrim(p_note), ''), v_phone
  ) returning id, order_number into v_order_id, v_order_number;

  for v_item in
    select (e.value ->> 'product_id')::uuid as product_id,
           (e.value ->> 'quantity')::integer as quantity
    from jsonb_array_elements(p_items_json) as e(value)
    order by (e.value ->> 'product_id')::uuid
  loop
    select * into v_product from public.products p where p.id = v_item.product_id;
    insert into public.order_items (
      order_id, product_id, product_name_snapshot, unit_price_iqd, quantity, line_total_iqd
    ) values (
      v_order_id, v_product.id, v_product.name, v_product.price_iqd, v_item.quantity,
      (v_product.price_iqd::bigint * v_item.quantity::bigint)::integer
    );
  end loop;

  return jsonb_build_object(
    'id', v_order_id,
    'order_number', v_order_number,
    'status', 'pending',
    'subtotal_iqd', v_subtotal::integer,
    'delivery_fee_iqd', v_store.delivery_fee_iqd,
    'total_iqd', v_total::integer,
    'commission_amount_iqd', v_commission,
    'store_net_payout_iqd', v_subtotal::integer - v_commission
  );
end;
$$;

create or replace function public.update_order_status(p_order_id uuid, p_new_status text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_order public.orders%rowtype;
  v_owner_id uuid;
  v_delivery_mode text;
  v_valid_transition boolean := false;
  v_is_owner boolean := false;
  v_is_assigned_driver boolean := false;
begin
  if v_uid is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  if p_new_status not in ('pending', 'accepted', 'preparing', 'on_the_way', 'delivered', 'rejected', 'cancelled') then
    raise exception 'Invalid order status';
  end if;

  select * into v_order from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  select s.owner_id, s.delivery_mode into v_owner_id, v_delivery_mode
  from public.stores s where s.id = v_order.store_id;
  select p.role into v_role from public.profiles p where p.id = v_uid and p.is_active;
  if v_role is null then raise exception 'Account is inactive'; end if;

  v_is_owner := v_owner_id = v_uid and v_role = 'seller';
  v_is_assigned_driver := v_order.driver_id = v_uid and v_role = 'driver';
  v_valid_transition := case v_order.status
    when 'pending' then p_new_status in ('accepted', 'rejected', 'cancelled')
    when 'accepted' then p_new_status = 'preparing'
    when 'preparing' then p_new_status = 'on_the_way'
    when 'on_the_way' then p_new_status = 'delivered'
    else false
  end;
  if not v_valid_transition then
    raise exception 'Invalid order transition: % -> %', v_order.status, p_new_status;
  end if;

  if public.is_admin() then
    null;
  elsif p_new_status = 'cancelled' then
    if v_order.buyer_id <> v_uid or v_order.status <> 'pending' then
      raise exception 'Only the buyer can cancel an order while it is pending';
    end if;
  elsif v_order.status = 'pending' and p_new_status in ('accepted', 'rejected') then
    if not v_is_owner then raise exception 'Only this store can accept or reject the order'; end if;
  elsif v_order.status = 'accepted' and p_new_status = 'preparing' then
    if not v_is_owner then raise exception 'Only this store can start preparing the order'; end if;
  elsif v_order.status = 'preparing' and p_new_status = 'on_the_way' then
    if not v_is_owner then raise exception 'Only this store can dispatch the order'; end if;
    if v_delivery_mode = 'platform_driver' and v_order.driver_id is null then
      raise exception 'Assign an active platform driver before dispatching this order';
    end if;
  elsif v_order.status = 'on_the_way' and p_new_status = 'delivered' then
    if not v_is_owner and not v_is_assigned_driver then
      raise exception 'Only this store, its assigned driver, or an admin can complete delivery';
    end if;
  else
    raise exception 'You are not allowed to make this order transition';
  end if;

  update public.orders
  set status = p_new_status,
      delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
      updated_at = now()
  where id = p_order_id
  returning * into v_order;

  return jsonb_build_object(
    'id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'updated_at', v_order.updated_at,
    'delivered_at', v_order.delivered_at
  );
end;
$$;

create or replace function public.assign_order_driver(p_order_id uuid, p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_order public.orders%rowtype;
  v_owner_id uuid;
  v_delivery_mode text;
  v_role text;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  select p.role into v_role from public.profiles p where p.id = auth.uid() and p.is_active;
  if v_role is null then raise exception 'Account is inactive'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  select owner_id, delivery_mode into v_owner_id, v_delivery_mode from public.stores where id = v_order.store_id;
  if not public.is_admin() and (v_role <> 'seller' or v_owner_id <> auth.uid()) then
    raise exception 'Only an active seller who owns the store or an admin can assign a driver';
  end if;
  if v_delivery_mode <> 'platform_driver' then
    raise exception 'This store is not using platform driver delivery';
  end if;
  if v_order.status not in ('accepted', 'preparing') then
    raise exception 'A driver can only be assigned to an accepted or preparing order';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = p_driver_id and p.role = 'driver' and p.is_active
  ) then raise exception 'The selected account is not an active driver'; end if;
  update public.orders set driver_id = p_driver_id, updated_at = now() where id = p_order_id;
end;
$$;

create or replace function public.list_active_drivers()
returns table(driver_id uuid, full_name text, city text)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_role text;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  select p.role into v_role from public.profiles p where p.id = auth.uid() and p.is_active;
  if v_role is null then raise exception 'Account is inactive'; end if;
  if not public.is_admin() and (v_role <> 'seller' or not exists (select 1 from public.stores s where s.owner_id = auth.uid())) then
    raise exception 'Only active sellers and admins may view available drivers' using errcode = '42501';
  end if;
  return query
  select p.id, p.full_name, p.city
  from public.profiles p
  where p.role = 'driver' and p.is_active
  order by p.full_name;
end;
$$;

-- Phone access is deliberately separate from the orders table SELECT grants.
create or replace function public.get_order_buyer_phone(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_order public.orders%rowtype;
  v_owner_id uuid;
  v_role text;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '28000'; end if;
  select * into v_order from public.orders where id = p_order_id;
  if not found then raise exception 'Order not found'; end if;
  select owner_id into v_owner_id from public.stores where id = v_order.store_id;
  select role into v_role from public.profiles where id = auth.uid() and is_active;
  if v_role is null then raise exception 'Account is inactive'; end if;

  if public.is_admin() or v_order.buyer_id = auth.uid() then
    return v_order.buyer_phone_snapshot;
  end if;
  if v_order.status in ('accepted', 'preparing', 'on_the_way', 'delivered')
     and ((v_owner_id = auth.uid() and v_role = 'seller') or (v_order.driver_id = auth.uid() and v_role = 'driver')) then
    return v_order.buyer_phone_snapshot;
  end if;
  raise exception 'Buyer contact details are available after the store accepts the order';
end;
$$;

create or replace function public.admin_set_store_approval(p_store_id uuid, p_is_approved boolean)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin access required' using errcode = '42501'; end if;
  update public.stores set is_approved = p_is_approved where id = p_store_id;
  if not found then raise exception 'Store not found'; end if;
  if p_is_approved then
    update public.profiles p
    set role = 'seller'
    where p.id = (select s.owner_id from public.stores s where s.id = p_store_id)
      and p.role = 'buyer';
  end if;
end;
$$;

create or replace function public.admin_update_store_financials(
  p_store_id uuid,
  p_commission_type text,
  p_commission_value numeric,
  p_delivery_mode text,
  p_delivery_fee_iqd integer
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin access required' using errcode = '42501'; end if;
  if p_commission_type not in ('percentage', 'fixed_iqd')
     or p_commission_value is null or p_commission_value < 0
     or (p_commission_type = 'percentage' and p_commission_value > 100)
     or p_delivery_mode not in ('platform_driver', 'store_self')
     or p_delivery_fee_iqd is null or p_delivery_fee_iqd < 0 then
    raise exception 'Invalid commission or delivery settings';
  end if;
  update public.stores
  set commission_type = p_commission_type,
      commission_value = p_commission_value,
      delivery_mode = p_delivery_mode,
      delivery_fee_iqd = p_delivery_fee_iqd
  where id = p_store_id;
  if not found then raise exception 'Store not found'; end if;
end;
$$;

create or replace function public.record_settlement(
  p_store_id uuid,
  p_amount_iqd integer,
  p_direction text default 'store_paid_platform',
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_balance bigint;
  v_settlement public.settlements%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin access required' using errcode = '42501'; end if;
  if p_amount_iqd is null or p_amount_iqd <= 0 then raise exception 'Settlement amount must be positive'; end if;
  if p_direction not in ('store_paid_platform', 'platform_paid_store') then raise exception 'Invalid settlement direction'; end if;
  if length(coalesce(p_note, '')) > 500 then raise exception 'Settlement note is too long'; end if;
  if not exists (select 1 from public.stores where id = p_store_id) then raise exception 'Store not found'; end if;

  -- Serialize ledger writes per store so an admin cannot concurrently over-collect.
  perform pg_advisory_xact_lock(hashtextextended(p_store_id::text, 0));
  select
    coalesce((select sum(o.commission_amount_iqd)::bigint
              from public.orders o where o.store_id = p_store_id and o.status = 'delivered'), 0)
    - coalesce((select sum(case s.direction when 'store_paid_platform' then s.amount_iqd else -s.amount_iqd end)::bigint
                from public.settlements s where s.store_id = p_store_id), 0)
  into v_balance;

  if p_direction = 'store_paid_platform' and p_amount_iqd::bigint > greatest(v_balance, 0) then
    raise exception 'Settlement exceeds the current commission balance (% IQD)', greatest(v_balance, 0);
  end if;

  insert into public.settlements (store_id, amount_iqd, direction, note, recorded_by)
  values (p_store_id, p_amount_iqd, p_direction, coalesce(btrim(p_note), ''), auth.uid())
  returning * into v_settlement;

  return jsonb_build_object(
    'id', v_settlement.id,
    'store_id', v_settlement.store_id,
    'amount_iqd', v_settlement.amount_iqd,
    'direction', v_settlement.direction,
    'note', v_settlement.note,
    'created_at', v_settlement.created_at
  );
end;
$$;

create or replace function public.admin_dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then raise exception 'Admin access required' using errcode = '42501'; end if;
  select jsonb_build_object(
    'today_orders', count(*) filter (where o.created_at >= date_trunc('day', now())),
    'month_orders', count(*) filter (where o.created_at >= date_trunc('month', now())),
    'today_gmv_iqd', coalesce(sum(o.subtotal_iqd) filter (where o.status = 'delivered' and o.delivered_at >= date_trunc('day', now())), 0),
    'month_gmv_iqd', coalesce(sum(o.subtotal_iqd) filter (where o.status = 'delivered' and o.delivered_at >= date_trunc('month', now())), 0),
    'lifetime_commission_iqd', coalesce(sum(o.commission_amount_iqd) filter (where o.status = 'delivered'), 0),
    'month_commission_iqd', coalesce(sum(o.commission_amount_iqd) filter (where o.status = 'delivered' and o.delivered_at >= date_trunc('month', now())), 0),
    'pending_stores', (select count(*) from public.stores s where not s.is_approved),
    'active_orders', (select count(*) from public.orders a where a.status in ('pending', 'accepted', 'preparing', 'on_the_way'))
  ) into v_result
  from public.orders o;
  return v_result;
end;
$$;

-- Prevent accidental public invocation of privileged routines. RLS helper routines are granted
-- separately because policies call them while evaluating authenticated and anonymous reads.
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.guard_order_financial_snapshots() from public, anon, authenticated;
revoke all on function public.guard_order_item_snapshots() from public, anon, authenticated;
revoke all on function public.guard_settlement_append_only() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.is_admin() from public, anon, authenticated;
revoke all on function public.owns_store(uuid) from public, anon, authenticated;
revoke all on function public.can_access_order(uuid) from public, anon, authenticated;
revoke all on function public.current_profile_role() from public, anon, authenticated;
revoke all on function public.get_store_commission_settings(uuid) from public, anon, authenticated;
revoke all on function public.admin_list_stores() from public, anon, authenticated;
revoke all on function public.quote_order(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.create_order(uuid, jsonb, double precision, double precision, text, text) from public, anon, authenticated;
revoke all on function public.update_order_status(uuid, text) from public, anon, authenticated;
revoke all on function public.assign_order_driver(uuid, uuid) from public, anon, authenticated;
revoke all on function public.list_active_drivers() from public, anon, authenticated;
revoke all on function public.get_order_buyer_phone(uuid) from public, anon, authenticated;
revoke all on function public.admin_set_store_approval(uuid, boolean) from public, anon, authenticated;
revoke all on function public.admin_update_store_financials(uuid, text, numeric, text, integer) from public, anon, authenticated;
revoke all on function public.record_settlement(uuid, integer, text, text) from public, anon, authenticated;
revoke all on function public.admin_dashboard_summary() from public, anon, authenticated;

grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.owns_store(uuid) to anon, authenticated;
grant execute on function public.can_access_order(uuid) to authenticated;
grant execute on function public.current_profile_role() to authenticated;
grant execute on function public.get_store_commission_settings(uuid) to authenticated;
grant execute on function public.admin_list_stores() to authenticated;
grant execute on function public.quote_order(uuid, jsonb) to authenticated;
grant execute on function public.create_order(uuid, jsonb, double precision, double precision, text, text) to authenticated;
grant execute on function public.update_order_status(uuid, text) to authenticated;
grant execute on function public.assign_order_driver(uuid, uuid) to authenticated;
grant execute on function public.list_active_drivers() to authenticated;
grant execute on function public.get_order_buyer_phone(uuid) to authenticated;
grant execute on function public.admin_set_store_approval(uuid, boolean) to authenticated;
grant execute on function public.admin_update_store_financials(uuid, text, numeric, text, integer) to authenticated;
grant execute on function public.record_settlement(uuid, integer, text, text) to authenticated;
grant execute on function public.admin_dashboard_summary() to authenticated;
