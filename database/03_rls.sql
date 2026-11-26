-- Enable and enforce row-level access for every application table.
-- Run this after functions.sql so the policy helper functions already exist.

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.stores enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.messages enable row level security;
alter table public.settlements enable row level security;

-- Start from no direct access; grant only the operations/columns the clients need.
revoke all on public.profiles, public.categories, public.stores, public.products,
  public.orders, public.order_items, public.messages, public.settlements
from anon, authenticated;
revoke all on public.store_financial_summary from anon, authenticated;

grant usage on schema public to anon, authenticated;

-- Discovery is intentionally public, but only approved stores and their available products.
-- Commission configuration is excluded from direct client reads; owners/admins fetch it through an authorized RPC.
grant select on public.categories, public.products to anon, authenticated;
grant select (
  id, owner_id, name, description, category_id, logo_url, cover_url, phone, city, address_text,
  latitude, longitude, is_open, is_approved, delivery_mode, delivery_fee_iqd, created_at
) on public.stores to anon, authenticated;

-- Profiles: users can see/edit only their own public profile fields. Role and active state are server-owned.
grant select on public.profiles to authenticated;
grant update (full_name, phone, city, fcm_token) on public.profiles to authenticated;

-- Store owners can apply and maintain their storefront, but cannot approve themselves or set commission.
grant insert (owner_id, name, description, category_id, logo_url, cover_url, phone, city,
              address_text, latitude, longitude, delivery_mode, delivery_fee_iqd)
  on public.stores to authenticated;
grant update (name, description, category_id, logo_url, cover_url, phone, city, address_text,
              latitude, longitude, is_open, delivery_mode, delivery_fee_iqd)
  on public.stores to authenticated;

-- Store owners manage only their products. Orders are created/changed only by trusted RPCs.
grant insert (store_id, name, description, price_iqd, image_url, is_available)
  on public.products to authenticated;
grant update (name, description, price_iqd, image_url, is_available)
  on public.products to authenticated;
grant delete on public.products to authenticated;

grant select (
  id, order_number, buyer_id, store_id, driver_id, status, payment_method,
  subtotal_iqd, delivery_fee_iqd, total_iqd,
  commission_type_snapshot, commission_value_snapshot, commission_amount_iqd, store_net_payout_iqd,
  delivery_lat, delivery_lng, delivery_address, buyer_note,
  created_at, updated_at, delivered_at
) on public.orders to authenticated;
-- buyer_phone_snapshot is intentionally not granted to any client role.

grant select on public.order_items to authenticated;
grant select on public.messages to authenticated;
grant insert (order_id, sender_id, body) on public.messages to authenticated;
grant select on public.settlements to authenticated;
grant select on public.store_financial_summary to authenticated;

grant insert, update, delete on public.categories to authenticated;
grant usage, select on sequence public.categories_id_seq to authenticated;

-- Categories are readable by buyers before login; only admins may change them.
drop policy if exists categories_read_all on public.categories;
create policy categories_read_all on public.categories
for select to anon, authenticated using (true);
drop policy if exists categories_admin_manage on public.categories;
create policy categories_admin_manage on public.categories
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Profiles.
drop policy if exists profiles_read_self_or_admin on public.profiles;
create policy profiles_read_self_or_admin on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_admin());
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update to authenticated
using (id = auth.uid() and is_active)
with check (id = auth.uid() and is_active);

-- Stores: public catalog visibility is limited to approved stores. Owners can inspect their own application.
drop policy if exists stores_public_approved_read on public.stores;
create policy stores_public_approved_read on public.stores
for select to anon, authenticated using (is_approved);
drop policy if exists stores_owner_read on public.stores;
create policy stores_owner_read on public.stores
for select to authenticated
using ((owner_id = auth.uid() and public.current_profile_role() is not null) or public.is_admin());
drop policy if exists stores_owner_create on public.stores;
create policy stores_owner_create on public.stores
for insert to authenticated
with check (owner_id = auth.uid() and not is_approved and public.current_profile_role() in ('buyer', 'seller'));
drop policy if exists stores_owner_update on public.stores;
create policy stores_owner_update on public.stores
for update to authenticated
using (owner_id = auth.uid() and public.current_profile_role() is not null)
with check (owner_id = auth.uid() and public.current_profile_role() is not null);

-- Products are visible publicly only when available in an approved store. Owners/admin can see all states.
drop policy if exists products_catalog_read on public.products;
create policy products_catalog_read on public.products
for select to anon, authenticated
using (
  is_available and exists (
    select 1 from public.stores s where s.id = store_id and s.is_approved
  )
);
drop policy if exists products_owner_admin_read on public.products;
create policy products_owner_admin_read on public.products
for select to authenticated
using (public.owns_store(store_id) or public.is_admin());
drop policy if exists products_owner_insert on public.products;
create policy products_owner_insert on public.products
for insert to authenticated
with check (public.owns_store(store_id));
drop policy if exists products_owner_update on public.products;
create policy products_owner_update on public.products
for update to authenticated
using (public.owns_store(store_id))
with check (public.owns_store(store_id));
drop policy if exists products_owner_delete on public.products;
create policy products_owner_delete on public.products
for delete to authenticated
using (public.owns_store(store_id));

-- Orders and line items are readable only to the buyer, the owning store, the assigned driver, or an admin.
drop policy if exists orders_participant_read on public.orders;
create policy orders_participant_read on public.orders
for select to authenticated using (public.can_access_order(id));
drop policy if exists order_items_participant_read on public.order_items;
create policy order_items_participant_read on public.order_items
for select to authenticated using (public.can_access_order(order_id));

-- Order chat stays private to the order's participants; messages cannot be edited or removed by clients.
drop policy if exists messages_participant_read on public.messages;
create policy messages_participant_read on public.messages
for select to authenticated using (public.can_access_order(order_id));
drop policy if exists messages_participant_insert on public.messages;
create policy messages_participant_insert on public.messages
for insert to authenticated
with check (
  sender_id = auth.uid()
  and public.can_access_order(order_id)
  and exists (
    select 1 from public.orders o
    where o.id = order_id and o.status not in ('delivered', 'rejected', 'cancelled')
  )
);

-- The financial ledger is visible to its store and admins, but all writes go through record_settlement().
drop policy if exists settlements_store_or_admin_read on public.settlements;
create policy settlements_store_or_admin_read on public.settlements
for select to authenticated
using (public.owns_store(store_id) or public.is_admin());

-- Optional public local storage backend. Uploads are limited to each user's own folder;
-- public reads are enabled for product/store images. Cloudinary can be selected instead.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('marketplace-images', 'marketplace-images', true, 122880, array['image/webp', 'image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists marketplace_images_public_read on storage.objects;
create policy marketplace_images_public_read on storage.objects
for select to anon, authenticated
using (bucket_id = 'marketplace-images');
drop policy if exists marketplace_images_owner_upload on storage.objects;
create policy marketplace_images_owner_upload on storage.objects
for insert to authenticated
with check (
  bucket_id = 'marketplace-images'
  and (storage.foldername(name))[1] = auth.uid()::text
  and public.current_profile_role() is not null
);
drop policy if exists marketplace_images_owner_update on storage.objects;
create policy marketplace_images_owner_update on storage.objects
for update to authenticated
using (bucket_id = 'marketplace-images' and (storage.foldername(name))[1] = auth.uid()::text and public.current_profile_role() is not null)
with check (bucket_id = 'marketplace-images' and (storage.foldername(name))[1] = auth.uid()::text and public.current_profile_role() is not null);
drop policy if exists marketplace_images_owner_delete on storage.objects;
create policy marketplace_images_owner_delete on storage.objects
for delete to authenticated
using (bucket_id = 'marketplace-images' and (storage.foldername(name))[1] = auth.uid()::text and public.current_profile_role() is not null);

-- Authenticated clients may never directly write financial order rows or settlement rows.
-- Orders are inserted and transitioned only by create_order/update_order_status SECURITY DEFINER RPCs.
-- Store approval/commission and settlement writes are similarly RPC-only.
