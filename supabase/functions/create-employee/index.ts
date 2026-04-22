import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Admin client (service role) — bypasses RLS for auth.admin operations
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // Caller client — used to verify the caller's identity and branch
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      {
        global: { headers: { Authorization: req.headers.get('Authorization')! } },
        auth: { autoRefreshToken: false, persistSession: false },
      },
    )

    // Verify the caller is authenticated
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser()
    if (authError || !caller) {
      return new Response(JSON.stringify({ error: 'No autenticado.' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Verify the caller is admin or supervisor
    const { data: callerProfile, error: profileError } = await adminClient
      .from('profiles')
      .select('role')
      .eq('id', caller.id)
      .single()

    if (profileError || !callerProfile) {
      return new Response(JSON.stringify({ error: 'Perfil no encontrado.' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!['admin', 'supervisor'].includes(callerProfile.role)) {
      return new Response(JSON.stringify({ error: 'Sin permisos para crear usuarios.' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get caller's default branch
    const { data: callerBranch, error: branchError } = await adminClient
      .from('users_branches')
      .select('branch_id')
      .eq('user_id', caller.id)
      .eq('is_default', true)
      .eq('is_active', true)
      .single()

    if (branchError || !callerBranch) {
      return new Response(JSON.stringify({ error: 'No hay sucursal activa para el administrador.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = await req.json()
    const { email, password, full_name, role, phone, employee_code, job_title, notes } = body

    if (!email || !password || !full_name || !role) {
      return new Response(JSON.stringify({ error: 'Campos requeridos: email, password, full_name, role.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Create the auth user — trigger will auto-create the profile row
    const { data: newUser, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name, role },
    })

    if (createError || !newUser.user) {
      return new Response(JSON.stringify({ error: createError?.message ?? 'Error al crear usuario.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const userId = newUser.user.id

    // Patch profile with extra fields (trigger may not have set all of them yet)
    const profilePatch: Record<string, unknown> = {
      full_name: full_name.trim(),
      role,
      is_active: true,
    }
    if (phone) profilePatch.phone = phone.trim()
    if (employee_code) profilePatch.employee_code = employee_code.trim()
    if (job_title) profilePatch.job_title = job_title.trim()
    if (notes) profilePatch.notes = notes.trim()

    await adminClient.from('profiles').update(profilePatch).eq('id', userId)

    // Assign user to the caller's branch as default
    const { error: branchAssignError } = await adminClient.from('users_branches').upsert(
      {
        user_id: userId,
        branch_id: callerBranch.branch_id,
        role_override: role,
        is_default: true,
        is_active: true,
        created_by: caller.id,
        updated_by: caller.id,
      },
      { onConflict: 'user_id,branch_id' },
    )

    if (branchAssignError) {
      // User was created — don't roll back, just report the partial failure
      return new Response(
        JSON.stringify({
          user_id: userId,
          warning: 'Usuario creado pero no se pudo asignar la sucursal: ' + branchAssignError.message,
        }),
        { status: 207, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(JSON.stringify({ user_id: userId }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
