DROP TRIGGER integration_lambda_trigger ON store CASCADE;
DROP FUNCTION integration_lambda;
DROP TABLE store;

CREATE EXTENSION IF NOT EXISTS aws_lambda CASCADE;

CREATE TABLE store (
  store_id SERIAL PRIMARY KEY,
  name_store VARCHAR(100) NOT NULL,
  address VARCHAR(100) NOT NULL,    
  segments VARCHAR(100) NOT NULL
);

CREATE FUNCTION integration_lambda() RETURNS TRIGGER AS $$
  DECLARE
    json_text TEXT;

  BEGIN 
    json_text := json_build_object('store_id', NEW.store_id, 'name_store', NEW.name_store, 'address', NEW.address, 'segments', NEW.segments);

    PERFORM aws_lambda.invoke(aws_commons.create_lambda_function_arn('arn:aws:lambda:us-east-1:AWS_ACCOUNT_NUMBER:function:change-data-capture','us-east-1'), json_text::json);
    
    return NEW;

  END;
$$ LANGUAGE plpgsql;
  

CREATE TRIGGER integration_lambda_trigger
  AFTER INSERT ON store
  FOR EACH ROW 
  EXECUTE FUNCTION integration_lambda()