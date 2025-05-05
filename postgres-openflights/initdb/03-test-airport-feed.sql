-- ==========================
-- Insert condition templates
-- ==========================

INSERT INTO condition_templates (name, description, target_type) VALUES
                                                                     ('fog',            'Low visibility due to fog',                      'airport'),
                                                                     ('wind',           'Strong wind at the airport',                     'airport'),
                                                                     ('temperature',    'Extreme temperature at the airport',            'airport'),
                                                                     ('low_altitude',   'Flight is below expected altitude threshold',   'flight'),
                                                                     ('high_speed',     'Flight is exceeding safe speed threshold',      'flight'),
                                                                     ('low_fuel',       'Fuel level is below safe operational threshold','flight');

-- ==========================
-- Insert normalized conditions
-- ==========================

INSERT INTO conditions (template_id, threshold, severity)
SELECT ct.id, vals.threshold, vals.severity
FROM (VALUES
          ('fog',           200,   1),
          ('wind',           30,   2),
          ('temperature',    35,   1),
          ('low_altitude', -3000,  3),  -- normalized
          ('high_speed',    500,   2),
          ('low_fuel',     -20,    3)   -- normalized
     ) AS vals(name, threshold, severity)
         JOIN condition_templates ct ON ct.name = vals.name;

-- ==========================
-- Identify dynamic test data
-- ==========================

WITH most_active_airport AS (
    SELECT destination_airport_id AS airport_id
    FROM routes
    GROUP BY destination_airport_id
    ORDER BY COUNT(*) DESC
    LIMIT 1
),
     selected_flight AS (
         SELECT f.id AS flight_id
         FROM flights f
                  JOIN most_active_airport a ON f.destination_airport_id = a.airport_id
         WHERE f.status IN ('scheduled', 'departed', 'delayed')
         ORDER BY f.departure_time ASC
         LIMIT 1
     ),

-- ==========================
-- Prepare normalized alert_conditions
-- ==========================

     airport_conditions AS (
         SELECT
             c.id AS condition_id,
             a.airport_id AS target_id,
             vals.value
         FROM most_active_airport a,
              condition_templates ct,
              conditions c,
              (VALUES
                   ('fog',        150),
                   ('wind',        40),
                   ('temperature', 33)
              ) AS vals(name, value)
         WHERE ct.name = vals.name
           AND ct.target_type = 'airport'
           AND c.template_id = ct.id
     ),

     flight_conditions AS (
         SELECT
             c.id AS condition_id,
             f.flight_id AS target_id,
            vals.value
         FROM selected_flight f,
              condition_templates ct,
              conditions c,
              (VALUES
                   ('low_altitude', -2500),
                   ('high_speed',    520),
                   ('low_fuel',       -15)
              ) AS vals(name, value)
         WHERE ct.name = vals.name
           AND ct.target_type = 'flight'
           AND c.template_id = ct.id
     )

-- ==========================
-- Insert alert_conditions
-- ==========================

-- Insert alert_conditions with current timestamp for received_at
INSERT INTO alert_conditions (condition_id, target_id, value, received_at)
SELECT condition_id, target_id, value, CURRENT_TIMESTAMP AT TIME ZONE 'UTC'  FROM airport_conditions
UNION ALL
SELECT condition_id, target_id, value, CURRENT_TIMESTAMP AT TIME ZONE 'UTC'  FROM flight_conditions;