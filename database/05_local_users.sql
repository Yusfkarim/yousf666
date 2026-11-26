-- Local deployment seed: roles, demo users, sample catalog data.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login password 'local-postgrest';
  end if;
end $$;
grant anon, authenticated, service_role to authenticator;
grant usage on schema public, auth, storage to authenticator;

create schema if not exists local_auth;
create table if not exists local_auth.users (
  email text primary key,
  password_hash text not null,
  user_id uuid not null references auth.users(id) on delete cascade
);
grant usage on schema local_auth to authenticator;
grant select (id, email) on auth.users to authenticator;
grant insert (id, email, raw_user_meta_data) on auth.users to authenticator;
grant select, insert, update on local_auth.users to authenticator;

-- User inserts fire the profile bootstrap trigger from functions.sql.
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'admin@yousf.local', '{"full_name":"بەڕێوەبەر"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'seller@yousf.local', '{"full_name":"فرۆشیار"}'::jsonb),
  ('33333333-3333-3333-3333-333333333333', 'buyer@yousf.local', '{"full_name":"کڕیار"}'::jsonb)
on conflict (id) do nothing;

update public.profiles set role = 'admin', is_active = true, full_name = 'بەڕێوەبەر'
  where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set role = 'seller', is_active = true, full_name = 'فرۆشیار'
  where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set role = 'buyer', is_active = true, full_name = 'کڕیار'
  where id = '33333333-3333-3333-3333-333333333333';

insert into local_auth.users (email, password_hash, user_id) values
  ('admin@yousf.local', '64eaad9605d1d2c487e0a52a82733e7e:221931ca65b20c04586a932e1b6d48831752bd8fab713e9d4926ec11c942ecd7', '11111111-1111-1111-1111-111111111111'),
  ('seller@yousf.local', '24741c965e2a5c76cf25bbf2ecb2d113:4b61eab87d7d18e2283009608a3ee631b81b7c7829cd2b241977b61721bcfec1', '22222222-2222-2222-2222-222222222222'),
  ('buyer@yousf.local', 'f5542db19f9e5ab3d7dfcb8d4a9b9151:1e3e3d0969b614a5520ac50cb33da403cc9792c76405c5dff90bfb2a0672b93a', '33333333-3333-3333-3333-333333333333')
on conflict (email) do update set password_hash = excluded.password_hash, user_id = excluded.user_id;

insert into public.stores (
  id, owner_id, name, description, category_id, city, address_text,
  phone, is_open, is_approved, delivery_mode, delivery_fee_iqd,
  commission_type, commission_value
) values (
  '44444444-4444-4444-4444-444444444444',
  '22222222-2222-2222-2222-222222222222',
  'مارکێتی نموونە',
  'کاڵای خۆراک و پێداویستی ڕۆژانە',
  2, 'هەولێر', 'شەقامی نموونە، ژمارە ١٠',
  '07701234567', true, true, 'platform_driver', 2000,
  'percentage', 10
)
on conflict (id) do nothing;

insert into public.products (store_id, name, description, price_iqd, is_available) values
  ('44444444-4444-4444-4444-444444444444', 'شیر', 'شیری تازەی یەک لیتر', 2500, true),
  ('44444444-4444-4444-4444-444444444444', 'نان', 'نانی تەندووری', 500, true),
  ('44444444-4444-4444-4444-444444444444', 'هێلکە', 'هێلکەی کێڵگە، ٣٠ دانە', 9000, true)
on conflict do nothing;
