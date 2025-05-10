-- ==========================
-- Insert condition templates
-- ==========================

-- Insert condition templates
INSERT INTO condition_templates (name, description, target_type) VALUES

-- Flight-related
('low_altitude',   'Flight is below expected altitude threshold',           'flight'),
('high_speed',     'Flight is exceeding safe speed threshold',              'flight'),
('low_fuel',       'Fuel level is below safe operational threshold',        'flight'),

-- Destination airport
('fog',            'Low visibility due to fog at destination airport',      'destination_airport'),
('wind',           'Strong wind at destination airport',                    'destination_airport'),
('temperature',    'Extreme temperature at destination airport',            'destination_airport'),
('runway_blocked', 'Runway temporarily blocked or unavailable',             'destination_airport'),
('arrival_delay',  'Congestion or delay in arrivals at destination airport','destination_airport'),

-- Source airport (operations + weather)
('departure_delay','Departure is delayed due to congestion at gate or ramp','source_airport'),
('deicing_needed', 'Deicing required at source airport',                    'source_airport'),
('low_visibility', 'Low visibility at source airport due to fog or haze',  'source_airport'),
('strong_headwind','Strong headwind impacting takeoff from source airport', 'source_airport'),
('heavy_rain',     'Heavy rain at source airport reducing visibility',       'source_airport'),
('thunderstorm',   'Thunderstorm activity near source airport',             'source_airport'),
('snowfall',       'Snowfall causing operational delays at source airport', 'source_airport'),
('crosswind_alert','Crosswind exceeding safe takeoff limits at source airport', 'source_airport');

-- ==========================
-- Insert normalized conditions
-- ==========================

INSERT INTO conditions (template_id, threshold, severity)
SELECT ct.id, vals.threshold, vals.severity
FROM (VALUES
          -- destination_airport
          ('fog',             200,   1),   -- visibility in meters
          ('wind',             30,   2),   -- wind in knots
          ('temperature',      35,   1),   -- temperature in Celsius
          ('runway_blocked',    1,   3),   -- boolean as 1/0
          ('arrival_delay',    15,   2),   -- delay in minutes

          -- source_airport
          ('departure_delay',  15,   2),
          ('deicing_needed',    1,   3),
          ('low_visibility',  500,   1),
          ('strong_headwind',  25,   2),
          ('heavy_rain',       10,   2),   -- mm/hour
          ('thunderstorm',      1,   3),
          ('snowfall',          2,   2),   -- cm/hour
          ('crosswind_alert',  20,   2),

          -- flight
          ('low_altitude',  -3000,  3),   -- altitude delta in feet (negative = below expected)
          ('high_speed',     500,   2),   -- knots
          ('low_fuel',       -20,   3)    -- % below minimum
     ) AS vals(name, threshold, severity)
         JOIN condition_templates ct ON ct.name = vals.name;