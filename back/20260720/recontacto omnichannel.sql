SELECT 
  SAFE_CAST(customer_id AS INT) AS customer_id, 
  entity_id, 
  customer_phone, 
  record_id,
  is_recontact_24_hrs AS is_recontact_24_hours,    
  creation_datetime as creation_dt, 
  channel,
  contact_channel_name,
  factory_name,
  service_agent_group_name as sag_name,
  employee_bp_number as bp_executive_number,
  next_contact_channel_name,
  next_record_id,
  next_creation_datetime as next_creation_dt,
  is_recontact_origin,
  is_recontact_24_hrs,

  CASE
    WHEN customer_phone IS NOT NULL OR customer_id IS NOT NULL OR entity_id IS NOT NULL THEN 1
    ELSE 0
  END AS is_traceable_contact,
  CASE
    WHEN (customer_phone IS NOT NULL OR customer_id IS NOT NULL OR entity_id IS NOT NULL) AND is_recontact_24_hrs = 1 THEN 1
    ELSE 0
  END AS is_traceable_recontact, 
  0 AS is_has_queue
FROM cuscare-data-prod.recontact.recontact_all_channels
#WHERE factory_name not in ('Almacontact GSS','Estado Agencias/Corporate','KONECTA BR GSS','Empresas')
