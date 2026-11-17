-- 0008_functions.sql : managed scope

-- Employees of every department that p_head_employee_id heads (the head is included when they sit in it).
-- Callers UNION their own employee id for the "managed" scope (FSD section 1).
CREATE FUNCTION managed_employee_ids(p_org uuid, p_head_employee_id uuid)
RETURNS SETOF uuid
LANGUAGE sql STABLE AS $$
  SELECT e.id
  FROM departments d
  JOIN employees e
    ON e.organization_id = d.organization_id AND e.department_id = d.id
  WHERE d.organization_id = p_org
    AND d.head_employee_id = p_head_employee_id
$$;
