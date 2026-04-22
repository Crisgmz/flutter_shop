-- Shop+ RD
-- Seed inicial para entorno de pruebas
-- Ejecutar despues de 01_schema.sql

begin;

do $$
declare
  v_branch_id uuid;
  v_admin_id uuid;
  v_any_user_id uuid;
  v_cash_session_id uuid;
  v_now timestamptz := timezone('utc', now());
begin
  -- 1) Sucursal principal
  insert into public.branches (
    code,
    name,
    address,
    phone,
    is_main,
    is_active
  )
  values (
    'MAIN',
    'Sucursal Principal',
    'Santo Domingo, RD',
    '809-000-0000',
    true,
    true
  )
  on conflict (code)
  do update set
    name = excluded.name,
    address = excluded.address,
    phone = excluded.phone,
    is_main = excluded.is_main,
    is_active = excluded.is_active,
    updated_at = timezone('utc', now())
  returning id into v_branch_id;

  if v_branch_id is null then
    select id into v_branch_id
    from public.branches
    where code = 'MAIN'
    limit 1;
  end if;

  -- 2) Usuario admin de pruebas (si existe en auth.users)
  select id
  into v_admin_id
  from auth.users
  where email = 'admin@shopplusrd.test'
  limit 1;

  v_any_user_id := coalesce(v_admin_id, (select id from auth.users limit 1));

  if v_admin_id is not null then
    insert into public.profiles (
      id,
      email,
      full_name,
      role,
      is_active
    )
    values (
      v_admin_id,
      'admin@shopplusrd.test',
      'Admin Test',
      'admin',
      true
    )
    on conflict (id)
    do update set
      email = excluded.email,
      full_name = excluded.full_name,
      role = excluded.role,
      is_active = excluded.is_active,
      updated_at = timezone('utc', now());

    insert into public.users_branches (
      user_id,
      branch_id,
      is_default,
      is_active,
      created_by,
      updated_by
    )
    values (
      v_admin_id,
      v_branch_id,
      true,
      true,
      v_admin_id,
      v_admin_id
    )
    on conflict (user_id, branch_id)
    do update set
      is_default = excluded.is_default,
      is_active = excluded.is_active,
      updated_at = timezone('utc', now()),
      updated_by = excluded.updated_by;
  end if;

  -- 3) Categorias
  insert into public.product_categories (
    id,
    branch_id,
    name,
    description,
    is_active,
    created_by,
    updated_by
  )
  values
    ('10000000-0000-4000-8000-000000000001', v_branch_id, 'Abarrotes', 'Productos de consumo masivo', true, v_admin_id, v_admin_id),
    ('10000000-0000-4000-8000-000000000002', v_branch_id, 'Bebidas', 'Bebidas frias y no alcoholicas', true, v_admin_id, v_admin_id),
    ('10000000-0000-4000-8000-000000000003', v_branch_id, 'Limpieza', 'Limpieza del hogar y negocio', true, v_admin_id, v_admin_id)
  on conflict (id)
  do update set
    name = excluded.name,
    description = excluded.description,
    is_active = excluded.is_active,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;

  -- 4) Productos
  insert into public.products (
    id,
    branch_id,
    category_id,
    sku,
    barcode,
    name,
    description,
    unit,
    cost,
    price,
    tax_rate,
    stock,
    min_stock,
    is_active,
    created_by,
    updated_by
  )
  values
    ('20000000-0000-4000-8000-000000000001', v_branch_id, '10000000-0000-4000-8000-000000000001', 'SKU-ARROZ-001', '7501234500001', 'Arroz Selecto 5lb', 'Arroz premium', 'unidad', 180.00, 250.00, 18.00, 0, 10, true, v_admin_id, v_admin_id),
    ('20000000-0000-4000-8000-000000000002', v_branch_id, '10000000-0000-4000-8000-000000000001', 'SKU-ACEITE-001', '7501234500002', 'Aceite Vegetal 900ml', 'Aceite para cocina', 'unidad', 130.00, 189.00, 18.00, 0, 8, true, v_admin_id, v_admin_id),
    ('20000000-0000-4000-8000-000000000003', v_branch_id, '10000000-0000-4000-8000-000000000002', 'SKU-REFRESCO-001', '7501234500003', 'Refresco Cola 2L', 'Bebida carbonatada', 'unidad', 70.00, 110.00, 18.00, 0, 12, true, v_admin_id, v_admin_id),
    ('20000000-0000-4000-8000-000000000004', v_branch_id, '10000000-0000-4000-8000-000000000003', 'SKU-DETERGENTE-001', '7501234500004', 'Detergente Liquido 1L', 'Limpieza general', 'unidad', 95.00, 149.00, 18.00, 0, 6, true, v_admin_id, v_admin_id)
  on conflict (id)
  do update set
    category_id = excluded.category_id,
    sku = excluded.sku,
    barcode = excluded.barcode,
    name = excluded.name,
    description = excluded.description,
    unit = excluded.unit,
    cost = excluded.cost,
    price = excluded.price,
    tax_rate = excluded.tax_rate,
    min_stock = excluded.min_stock,
    is_active = excluded.is_active,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;

  -- 5) Clientes
  insert into public.clients (
    id,
    branch_id,
    entity_type,
    full_name,
    legal_name,
    email,
    phone,
    address,
    document_type,
    document_number,
    credit_limit,
    balance_due,
    is_active,
    created_by,
    updated_by
  )
  values
    ('30000000-0000-4000-8000-000000000001', v_branch_id, 'person', 'Juan Perez', null, 'juan.perez@test.com', '809-100-1001', 'Santo Domingo', 'cedula', '00112345678', 15000, 0, true, v_admin_id, v_admin_id),
    ('30000000-0000-4000-8000-000000000002', v_branch_id, 'person', 'Maria Garcia', null, 'maria.garcia@test.com', '809-100-1002', 'Santo Domingo', 'cedula', '00187654321', 8000, 0, true, v_admin_id, v_admin_id),
    ('30000000-0000-4000-8000-000000000003', v_branch_id, 'company', 'Empresa XYZ', 'Empresa XYZ SRL', 'compras@empresaxyz.com', '809-200-9000', 'Distrito Nacional', 'rnc', '132456789', 50000, 0, true, v_admin_id, v_admin_id)
  on conflict (id)
  do update set
    full_name = excluded.full_name,
    legal_name = excluded.legal_name,
    email = excluded.email,
    phone = excluded.phone,
    address = excluded.address,
    document_type = excluded.document_type,
    document_number = excluded.document_number,
    credit_limit = excluded.credit_limit,
    is_active = excluded.is_active,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;

  -- 6) Proveedores
  insert into public.suppliers (
    id,
    branch_id,
    legal_name,
    trade_name,
    email,
    phone,
    address,
    rnc,
    contact_name,
    is_active,
    created_by,
    updated_by
  )
  values
    ('40000000-0000-4000-8000-000000000001', v_branch_id, 'Distribuidora Central SRL', 'DICEN', 'ventas@dicen.com', '809-555-0001', 'Santo Domingo Oeste', '131000111', 'Carlos Mendez', true, v_admin_id, v_admin_id),
    ('40000000-0000-4000-8000-000000000002', v_branch_id, 'Mayorista del Caribe SRL', 'MAYCAR', 'pedidos@maycar.com', '809-555-0002', 'Santiago', '131000222', 'Laura Santos', true, v_admin_id, v_admin_id)
  on conflict (id)
  do update set
    legal_name = excluded.legal_name,
    trade_name = excluded.trade_name,
    email = excluded.email,
    phone = excluded.phone,
    address = excluded.address,
    rnc = excluded.rnc,
    contact_name = excluded.contact_name,
    is_active = excluded.is_active,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;

  -- 7) Secuencias NCF (impuestos)
  insert into public.ncf_sequences (
    id,
    branch_id,
    receipt_type,
    prefix,
    current_number,
    max_number,
    expires_on,
    is_active,
    created_by,
    updated_by
  )
  values
    ('50000000-0000-4000-8000-000000000001', v_branch_id, 'fiscal_credit', 'B0100000', 45, 500, current_date + interval '365 days', true, v_admin_id, v_admin_id),
    ('50000000-0000-4000-8000-000000000002', v_branch_id, 'consumer_final', 'B0200000', 123, 500, current_date + interval '365 days', true, v_admin_id, v_admin_id),
    ('50000000-0000-4000-8000-000000000003', v_branch_id, 'governmental', 'B1500000', 12, 200, current_date + interval '365 days', true, v_admin_id, v_admin_id)
  on conflict (id)
  do update set
    prefix = excluded.prefix,
    current_number = excluded.current_number,
    max_number = excluded.max_number,
    expires_on = excluded.expires_on,
    is_active = excluded.is_active,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;

  -- 8) Compra demo + item (sube inventario por trigger)
  insert into public.purchases (
    id,
    branch_id,
    supplier_id,
    purchase_number,
    invoice_number,
    status,
    purchase_date,
    notes,
    subtotal,
    discount_amount,
    tax_amount,
    total_amount,
    created_by,
    updated_by
  )
  values (
    '60000000-0000-4000-8000-000000000001',
    v_branch_id,
    '40000000-0000-4000-8000-000000000001',
    'COMP-0001',
    'FAC-2026-0001',
    'posted',
    current_date - 1,
    'Compra inicial de inventario',
    16500.00,
    0,
    2970.00,
    19470.00,
    v_admin_id,
    v_admin_id
  )
  on conflict (id)
  do update set
    supplier_id = excluded.supplier_id,
    status = excluded.status,
    purchase_date = excluded.purchase_date,
    subtotal = excluded.subtotal,
    discount_amount = excluded.discount_amount,
    tax_amount = excluded.tax_amount,
    total_amount = excluded.total_amount,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;

  if not exists (
    select 1
    from public.purchase_items
    where id = '61000000-0000-4000-8000-000000000001'
  ) then
    insert into public.purchase_items (
      id,
      purchase_id,
      branch_id,
      product_id,
      description,
      quantity,
      unit_cost,
      discount_amount,
      tax_rate,
      line_subtotal,
      line_tax,
      line_total,
      created_by,
      updated_by
    )
    values
      ('61000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000001', v_branch_id, '20000000-0000-4000-8000-000000000001', 'Arroz Selecto 5lb', 40, 180.00, 0, 18.00, 7200.00, 1296.00, 8496.00, v_admin_id, v_admin_id),
      ('61000000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000001', v_branch_id, '20000000-0000-4000-8000-000000000002', 'Aceite Vegetal 900ml', 30, 130.00, 0, 18.00, 3900.00, 702.00, 4602.00, v_admin_id, v_admin_id),
      ('61000000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000001', v_branch_id, '20000000-0000-4000-8000-000000000003', 'Refresco Cola 2L', 50, 70.00, 0, 18.00, 3500.00, 630.00, 4130.00, v_admin_id, v_admin_id),
      ('61000000-0000-4000-8000-000000000004', '60000000-0000-4000-8000-000000000001', v_branch_id, '20000000-0000-4000-8000-000000000004', 'Detergente Liquido 1L', 20, 95.00, 0, 18.00, 1900.00, 342.00, 2242.00, v_admin_id, v_admin_id);
  end if;

  -- 9) Caja abierta
  select id
  into v_cash_session_id
  from public.cash_sessions
  where branch_id = v_branch_id
    and status = 'open'
  order by opened_at desc
  limit 1;

  if v_cash_session_id is null and v_any_user_id is not null then
    v_cash_session_id := '70000000-0000-4000-8000-000000000001';
    insert into public.cash_sessions (
      id,
      branch_id,
      opened_by,
      status,
      opened_at,
      opening_amount,
      expected_amount,
      notes,
      created_by,
      updated_by
    )
    values (
      v_cash_session_id,
      v_branch_id,
      v_any_user_id,
      'open',
      v_now,
      10000.00,
      10000.00,
      'Caja inicial de pruebas',
      v_admin_id,
      v_admin_id
    )
    on conflict (id)
    do update set
      status = excluded.status,
      opening_amount = excluded.opening_amount,
      expected_amount = excluded.expected_amount,
      notes = excluded.notes,
      updated_at = timezone('utc', now()),
      updated_by = excluded.updated_by;
  end if;

  -- 10) Venta demo + item + pago
  insert into public.sales (
    id,
    branch_id,
    sale_number,
    client_id,
    cashier_id,
    receipt_type,
    ncf,
    dgii_status,
    status,
    sale_date,
    subtotal,
    discount_amount,
    tax_amount,
    total_amount,
    paid_amount,
    balance_due,
    notes,
    created_by,
    updated_by
  )
  values (
    '80000000-0000-4000-8000-000000000001',
    v_branch_id,
    'VENTA-0001',
    '30000000-0000-4000-8000-000000000001',
    v_admin_id,
    'fiscal_credit',
    'B0100000045',
    'approved',
    'completed',
    v_now,
    809.40,
    0,
    145.69,
    955.09,
    955.09,
    0,
    'Venta de demostracion',
    v_admin_id,
    v_admin_id
  )
  on conflict (id)
  do update set
    sale_number = excluded.sale_number,
    client_id = excluded.client_id,
    receipt_type = excluded.receipt_type,
    ncf = excluded.ncf,
    dgii_status = excluded.dgii_status,
    status = excluded.status,
    subtotal = excluded.subtotal,
    tax_amount = excluded.tax_amount,
    total_amount = excluded.total_amount,
    paid_amount = excluded.paid_amount,
    balance_due = excluded.balance_due,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;

  if not exists (
    select 1
    from public.sale_items
    where id = '81000000-0000-4000-8000-000000000001'
  ) then
    insert into public.sale_items (
      id,
      sale_id,
      branch_id,
      product_id,
      description,
      quantity,
      unit_price,
      discount_amount,
      tax_rate,
      line_subtotal,
      line_tax,
      line_total,
      created_by,
      updated_by
    )
    values
      ('81000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000001', v_branch_id, '20000000-0000-4000-8000-000000000001', 'Arroz Selecto 5lb', 2, 250.00, 0, 18.00, 500.00, 90.00, 590.00, v_admin_id, v_admin_id),
      ('81000000-0000-4000-8000-000000000002', '80000000-0000-4000-8000-000000000001', v_branch_id, '20000000-0000-4000-8000-000000000003', 'Refresco Cola 2L', 2, 110.00, 0, 18.00, 220.00, 39.60, 259.60, v_admin_id, v_admin_id),
      ('81000000-0000-4000-8000-000000000003', '80000000-0000-4000-8000-000000000001', v_branch_id, '20000000-0000-4000-8000-000000000004', 'Detergente Liquido 1L', 0.6, 149.00, 0, 18.00, 89.40, 16.09, 105.49, v_admin_id, v_admin_id);
  end if;

  insert into public.payments (
    id,
    branch_id,
    sale_id,
    client_id,
    cash_session_id,
    payment_method,
    amount,
    paid_at,
    reference,
    notes,
    created_by,
    updated_by
  )
  values (
    '90000000-0000-4000-8000-000000000001',
    v_branch_id,
    '80000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    v_cash_session_id,
    'cash',
    955.09,
    v_now,
    'REC-0001',
    'Pago total de venta demo',
    v_admin_id,
    v_admin_id
  )
  on conflict (id)
  do update set
    payment_method = excluded.payment_method,
    amount = excluded.amount,
    reference = excluded.reference,
    notes = excluded.notes,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;

  -- 11) Gasto demo
  insert into public.expenses (
    id,
    branch_id,
    cash_session_id,
    category,
    description,
    payment_method,
    amount,
    expense_date,
    created_by,
    updated_by
  )
  values (
    '91000000-0000-4000-8000-000000000001',
    v_branch_id,
    '70000000-0000-4000-8000-000000000001',
    'Servicios',
    'Compra de material de limpieza',
    'cash',
    1200.00,
    current_date,
    v_admin_id,
    v_admin_id
  )
  on conflict (id)
  do update set
    category = excluded.category,
    description = excluded.description,
    amount = excluded.amount,
    expense_date = excluded.expense_date,
    updated_at = timezone('utc', now()),
    updated_by = excluded.updated_by;
end $$;

commit;
