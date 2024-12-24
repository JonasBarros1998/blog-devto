## Introdução

### Visão geral
Change Data Capture ou CDC é um método utilizado para extrair dados de uma base primária para uma outra base de destino utilizando algum conector viabilizar esta comunicação

![image](https://github.com/user-attachments/assets/036e19c7-a1aa-47fe-85b9-b81b64b8a4cc)

Este conector será ativado quando ocorrer um evento no qual irá alterar o estado da sua base de dados primária.

Após a ocorrência deste evento, o conector será ativado recebendo os dados que foram alterados, com estes dados em mãos nós podemos enviá-los para outro ambiente, como por exemplo uma outra base de dados no qual sua funcionalidade principal é ser um data lake.

Existem diversas ferramentas que poderíamos escolher para desenvolvermos o nosso fluxo de change data capture. O Dynamodb streams e AWS RDS com SQL Server são algumas ferramentas que possuem a funcionalidade de captura de eventos e migração de dados de forma nativa. Mas também podemos criar o nosso próprio change data capture utilizando os triggers do PostgreSQL para capturar as mudanças de estados e enviá-las ao conector. 

Portanto ao decorrer deste artigo, irei mostrar como poderemos criar o nosso próprio fluxo de change data capture utilizando o AWS RDS Aurora PostgreSQL, criaremos os triggers para observarmos as mudanças de estado e utilizaremos a extensão aws_lambda para enviar os dados ao conector AWS lambda.

### Quando utilizar 
- Se a base de dados primária for um data lake, podemos criar um fluxo CDC para notificar o conector a cada novo item que for inserido na tabela. O conector poderá estruturar os dados e enviá-los ao data warehouse.  

- O dynamodb possui um recurso chamado dynamodb streams, com ele nós conseguimos notificar outros serviços da AWS quando houver uma alteração de estado em algum item da tabela.

- Podemos instalar a extensão aws_lambda no AWS RDS Aurora PostgreSQL para noticiar um conector como por exemplo um AWS lambda quando o estado de alguma tabela for alterada

- Se tivermos implementando logs de auditoria, podemos aproveitar os recursos dos triggers do PostgreSQL para notificar os conectores quando houver um evento de inserção (insert), Atualização (update) ou Exclusão (delete) em uma ou múltiplas linhas da tabela. 

### Quando não utilizar 
- Ao utilizar para construção simples tarefas, como envio de e-mail ou semelhantes notificações a cada momento que um novo item é inserido.

- Quando a sua base de dados é muito pequena para se fazer essas transferências de dados, já que para construção deste fluxo acarretará em um aumento do custo mensal da conta AWS. 

- Se você possuir uma base em uma versão do RDS que não é compatível com a extensão aws_lambda, não será necessário migrar toda a sua base dados ao AWS RDS Aurora, é possível utilizar outras estratégias para criar um fluxo de dados CDC. 

## Criando um change data capture utilizando um cluster AWS RDS Aurora PostgreSQL

Nos tópicos a seguir será apresentado como criar a infraestrutura inicial para um fluxo CDC no AWS Aurora PostgreSQL. Segue o link do repositório contendo todos os recursos necessários para iniciar a construção. 

Repositório: [Change data capture com AWS RDS Aurora PostgreSQL](https://github.com/JonasBarros1998/blog-devto/tree/main/change-data-capture-com-aws-rds-postgresql)

### Criando e configurando o cluster AWS RDS PostgreSQL

Utilizando o módulo [aurora_postgresql_v2](https://registry.terraform.io/modules/terraform-aws-modules/rds-aurora/aws/latest) nós podemos começar a criação de um [cluster e uma instância do aurora PostgreSQL](https://github.com/JonasBarros1998/blog-devto/blob/main/change-data-capture-com-aws-rds-postgresql/infra/main.tf#L57). 
Para que não haja custos elevados, sua configuração foi a mais básica possível, evitando adicionar outros recursos como escalabilidade e segurança no cluster RDS. 

Como nós criamos o cluster dentro de uma VPC, precisaríamos adicionar novos recursos para permitir a conexão entre máquina local e instância RDS. Um exemplo muito comum é criar uma instância EC2 que irá fazer a ponte e permitir a conexão entre máquina local e instância RDS. Porém fazer esse processo também envolve custos,
portanto para que não tenhamos custos elevados enquanto estamos estudando o CDC, nós criamos a instância de forma [pública](https://github.com/JonasBarros1998/blog-devto/blob/main/change-data-capture-com-aws-rds-postgresql/infra/main.tf#L79)

```tf
vpc_id                 = "vpc-0000000" # adicione o ID VPC da sua conta AWS 
db_subnet_group_name   = "default-vpc-0000" # adicione a subnet da conta AWS
security_group_name    = "security" # adicione o security group name da conta AWS
publicly_accessible    = true # acesso público

```

Para realizar a conexão entre máquina local e cluster, podemos utilizar a porta 5432. 

Para que a conexão entre lambda e cluster ocorra com sucesso, precisamos adicionar regras de entrada e saída. Dentro desta regra adicionamos um range com IP padrão apenas para fins de demonstração, mas em um ambiente produtivo configure corretamente o range de IP no qual o cluster aceitará receber conexões. 

A senha que precisamos para se conectar ao banco, é gerada automaticamente e adicionada no **secret manager**. Portanto, 
para fazer a conexão com o cluster, acesse o secret manager no console AWS e copie a senha armazenada. 

``` tf
security_group_rules = {
  ex1_ingress = {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = "5432"
    to_port = "5432"
    protocol = "tcp"
    type = "ingress"
  }

  ex2_ingress = {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = "443"
    to_port = "443"
    protocol = "tcp"
    type = "ingress"
  }

  ex3_egress = {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = "443"
    to_port = "443"
    protocol = "tcp"
    type = "egress"
  }

  ex4_egress = {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = "5432"
    to_port = "5432"
    protocol = "tcp"
    type = "egress"
  }

```

### Configurando o IAM

Como vimos no tópico anterior, foi preciso adicionar uma regra para aceitar conexões na porta 443 entre cluster e lambda. 
Mas não é só isso, precisamos também configurar políticas e roles para que a conexão entre os dois serviços seja realizada com sucesso. 

Criamos uma role do tipo Principal. Só com ela conseguiremos gerar credenciais temporárias para possibilitar a chamada do cluster para a lambda

```
data "aws_iam_policy_document" "change-data-capture-document-role-cluster-rds" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "change-data-capture-role-cluster-rds" {
  name               = "change-data-capture-role"
  assume_role_policy = data.aws_iam_policy_document.change-data-capture-document-role-cluster-rds.json
}

```

Em seguida criamos uma política com uma ação de `lambda:InvokeFunction`, o objetivo é dizer ao cluster que ele está habilitado a fazer chamadas a nossa função lambda, 
que criaremos logo em seguida. 

Com os recursos criados, agora só precisamos adicionar a role dentro do módulo postgreSQL

```
data "aws_iam_policy_document" "change-data-capture-ducument-policy-cluster-rds" {
  statement {
    sid = "ChangeDataCapturePolicy"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]

    resources = [
      "arn:aws:lambda:us-east-1:AWS_ACOUNT_ID:function:${var.lambda_name}"
    ]
  }
}

# anexamos a policy que criamos acima, dentro da nossa role
resource "aws_iam_role_policy_attachment" "change-data-capture-role-attachment-cluster-rds" {
  policy_arn = aws_iam_policy.change-data-capture-policy-cluster-rds.arn
  role = aws_iam_role.change-data-capture-role-cluster-rds.name
}

# dentro do modulo postgreSQL, adicionamos a role que criamos anteriormente
iam_roles = {
    lambda = {
      role_arn     = aws_iam_role.change-data-capture-role-cluster-rds.arn
      feature_name = "Lambda"
    }
  }

```

### Criando a função lambda

Agora que terminamos a configuração do módulo postgresql e toda a estrutura de comunicação com outros serviços, precisamos criar e configurar a nossa lambda. 

Precisei criar uma nova ***role do tipo Principal*** para geração de credenciais temporárias. Esse é o processo padrão para criação de qualquer lambda

```
data "aws_iam_policy_document" "change-data-capture-document-lambda-role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "change-data-capture-role-lambda" {
  name               = "change-data-capture-lambda-document"
  assume_role_policy = data.aws_iam_policy_document.change-data-capture-document-lambda-role.json
}

```
Em seguida, precisamos criar as políticas de acesso e a criação do recurso do ***cloudWatch***. 
Sem eles a lambda não conseguiremos observar o resultado da integração entre banco e lambda.

```
resource "aws_iam_policy" "change-data-capture-lambda-policy" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.change-data-capture-ducument-policy-cloud-watch.json
}

resource "aws_iam_role_policy_attachment" "change-data-capture-policy-attachment-lambda" {
  policy_arn = aws_iam_policy.change-data-capture-lambda-policy.arn
  role       = aws_iam_role.change-data-capture-role-lambda.name
}

resource "aws_cloudwatch_log_group" "change-data-capture-cloudwatch" {
  name              = "/aws/lambda/${var.lambda_name}"
  retention_in_days = 14
}

```

Em seguida precisaremos dizer ao terraform qual é o arquivo que será inserido na lambda. Para isso criei um recurso que me diz qual o caminho para o arquivo ZIP, no qual deverá conter todo código fonte que utilizaremos. \
[Segue o repositório contendo o código fonte desenvolvido em Javascript](https://github.com/JonasBarros1998/blog-devto/tree/main/change-data-capture-com-aws-rds-postgresql/src). Desenvolvemos algo bem simples, apenas enviamos ao CloudWatch o que a lambda está recebendo ao ser chamada pelo banco de dados. 

```
data "archive_file" "change-data-capture-archive-file" {
  type        = "zip"
  source_dir  = "../src"
  output_path = "change-data-capture-function-payload.zip"
}

resource "aws_lambda_function" "change-data-capture-function" {
  filename      = "change-data-capture-function-payload.zip"
  function_name = var.lambda_name
  role          = aws_iam_role.change-data-capture-role-lambda.arn
  handler       = "main.handler"
  source_code_hash = data.archive_file.change-data-capture-archive-file.output_base64sha256
  runtime = "nodejs20.x"
  depends_on = [ 
    aws_iam_role_policy_attachment.change-data-capture-policy-attachment-lambda, 
    aws_cloudwatch_log_group.change-data-capture-cloudwatch
  ]
}

```

## Conectando o AWS RDS com a função lambda 

Antes de fazer os passos abaixo, certifique que os recursos foram criados corretamente quando rodou o comando terraform apply. Na AWS, acesse o secret manager e identifique a senha que foi criada quando o terraform foi executado. Copie e deixe-a separada já que iremos utilizá-la para se conectar com o banco.
A senha mudará a cada momento em que você fazer o destroy da infra e recriá-la novamente. 

### Conectando com o banco de dados

Na AWS acesse o RDS e identifique o cluster que foi criado. Ao selecionar o cluster, pegue a string de conexão, pois ela será necessária para fazermos a conexão entre a máquina local com o nosso banco de dados. A string de conexão deverá ter o seguinte formato:

`{nome-do-cluster}.{numero-identificador}.{regiao}.rds.amazonaws.com`

Para fazer a conexão com o banco, utilize o seguinte comando:

`psql -h {nome-do-cluster}.{identificador-unico}.{regiao}.rds.amazonaws.com -U cdcStoreDevTo -p 5432 -d cdcstore`


`-h = host de conexão`
`-U = nome do usuário`
`-p = porta de conexão com o banco`
`-d = nome da database`

Ao fazer o comando acima, vai aparecer no terminal um prompt para digitar a senha, portanto utilize a senha que foi criada e armazenada dentro do secret manager.
Se a conexão for realizada com sucesso, você estará neste momento dentro da instância cdcstore

### Instalando a extensão aws_lambda

Após realizar a conexão com a instância, instale a extensão `aws_lambda`. Mas para que seja possível fazer a chamada, precisamos também instalar a extensão `aws_commons`. 
Ao inserir o comando abaixo, será instalada ambas as extensões que precisaremos para enviamos dados ao aws lambda. 

```sql
CREATE EXTENSION IF NOT EXISTS aws_lambda CASCADE;
```

#### Mas o que são extensões no postgreSQL? 

A extensão é uma funcionalidade que você pode criar para fazer alguns trabalhos extras. Uma extensão bastante famosa no postgreSQL é o hstore, com ela nós podemos armazenar um conjunto de chave/valor em um único registro. Veja o exemplo abaixo, nós utilizamos a extensão como um tipo para o campo `products`, e adicionamos os dados chave/valor. 


```sql
CREATE EXTENSION hstore;
CREATE TABLE store (products hstore);
INSERT INTO store VALUES ('a=>b, c=>d');

--consulta pelo item a
SELECT products['a'] from store;

-- consulta pelo item b
SELECT products['c'] from store;

```

A `aws_lambda` também é uma extensão. Como dizemos anteriormente, as extensões vão fazer um trabalho extra, ou aprimorar alguma funcionalidade como vimos com hstore.
Veja que com o hstore é possível utilizar uma chave para consultar um único item ou um conjunto deles, dependendo dos valores que foram adicionados. 

Também é possível criar as nossas próprias extensões no postgreSQL. Para isso podemos criar um arquivo `nome_do_arquivo.sql`, e adicionar todo o conteúdo da extensão dentro dele, e salvaremos esse arquivo dentro do diretório de instalação do postgreSQL na pasta /extension. Para encontrar o diretório de instalação consulte a documentação oficial do banco. Mas para sistemas operacionais baseados em linux, possivelmente irá encontrá-lo no seguinte caminho:`/usr/share/postgresql/{NUMERO_DA_VERSAO_DO_POSTGRESQL}/extension`

Após escrevemos a nossa extensão e inseri-la na pasta /extension, podemos instalar a extensão com o comando a seguir. Após instalada, poderá ser utilizada normalmente conforme você desenvolveu. 

```sql
CREATE EXTENSION nome_extensão;
```
Porém como estamos trabalhando com RDS, não será possível acessarmos o diretório de instalação do postgreSQL para criarmos as nossas extensões, logo teremos que utilizar uma nova abordagem chamada [TLE - Trusted Language Extensions](https://docs.aws.amazon.com/pt_br/AmazonRDS/latest/UserGuide/PostgreSQL_trusted_language_extension-terminology.html).

Trusted Language Extension é um kit de desenvolvimento de código aberto utilizado para criar as nossas extensões de maneira segura. Como foi visto anteriormente, para instalar as extensões da maneira padrão, é necessário criar um script dentro da pasta /extension localizado no diretório de instalação do postgreSQL. Porém, por motivos de segurança o RDS não possibilita o acesso ao sistema de arquivos da máquina no qual está rodando a instância. E se desejarmos criar a nossa extensão para rodar dentro do RDS será necessário utilizar o kit de desenvolvimento TLE. 

Quando instalamos o TLE, temos disponíveis o que chamamos de linguagens seguras para desenvolver os nossos scripts, como por exemplo o PL/V8 no qual é uma biblioteca que fornece uma linguagem procedural para PostgreSQL que utiliza o V8 JavaScript Engine. Ao utilizá-la nós não conseguiremos acessar ou manipular quaisquer conteúdos dentro do sistema de arquivos da instância que roda o banco de dados. 

Na [documentação do PostgreSQL](https://www.postgresql.org/docs/current/plperl-trusted.html) temos um exemplo no qual seremos barrados ao tentarmos criar um arquivo dentro do diretório /tmp. Este exemplo foi feito utilizando o PL/PERL no qual também é uma versão segura para criarmos as nossas extensões. 

```
CREATE FUNCTION badfunc() RETURNS integer AS $$
    my $tmpfile = "/tmp/badfile";
    open my $fh, '>', $tmpfile
        or elog(ERROR, qq{could not open the file "$tmpfile": $!});
    print $fh "Testing writing to a file\n";
    close $fh or elog(ERROR, qq{could not close the file "$tmpfile": $!});
    return 1;
$$ LANGUAGE plperl;
``` 

O comando a seguir pressupõe que você já tenha criado um grupo de parâmetros para a sua instância, então você só precisará substituir a variável ADD_PARAMETER_GROUP_NAME pelo nome do grupo de parâmetros.  Ao final deste tópico terá um link para a documentação auxiliando na criação de um grupo de parâmetros para a instância que você está utilizando.


```
aws rds modify-db-parameter-group \
--db-parameter-group-name ADD_PARAMETER_GROUP_NAME \
--parameters"ParameterName=shared_preload_libraries,ParameterValue=pg_tle,ApplyMethod=pending-reboot" \
--region aws-region

```
No comando acima nós estamos dizendo ao RDS para inicializar a extensão pg_tle na instância que está vinculada ao grupo de parâmetros. 

Se não houver nenhum erro ao executar o comando acima você deverá reiniciar a instância e logo em seguida baixar a extensão e executar o seguinte comando: 

```sql
CREATE EXTENSION NOME_EXTENSAO;
```

Segue alguns links úteis no qual explicam com mais detalhes sobre o TLE e nos ensinam a desenvolver nossas primeiras extensões. 

- [Como fazer a configurar e instalar uma extensão utilizando AWS CLI](https://github.com/aws/pg_tle/blob/main/docs/01_install.md#method-3-amazon-rds--amazon-aurora-only-use-parameter-groups)
- [Como fazer a instalação utilizando console AWS](https://docs.aws.amazon.com/pt_br/AmazonRDS/latest/UserGuide/PostgreSQL_trusted_language_extension-setting-up.html)
- [Exemplos de extensões utilizando o SQL](https://github.com/aws/pg_tle/blob/main/docs/02_quickstart.md)
- [Exemplos de extensões utilizando o PL/V8](https://github.com/aws/pg_tle/blob/main/docs/07_plv8_examples.md)
- [Link da documentação completa no repositório oficial do pg_tle](https://github.com/aws/pg_tle?tab=readme-ov-file#trusted-language-extensions-for-postgresql-pg_tle)
- [Criação de um grupo de parâmetros](https://docs.aws.amazon.com/cli/latest/reference/rds/create-db-parameter-group.html)

As extensões hstore e aws_lambda já vem pré-carregada dentro da instância aurora-postgresql portanto não será necessário realizar os descritos acima.

## Testando funcionalidade

Vamos fazer um primeiro teste simples. Vamos utilizar a função `create_lambda_function_arn` e passar o ARN da nossa lambda, em seguida passaremos uma string contendo apenas uma simples mensagem e converteremos esse valor para o tipo json

```sql
SELECT * from aws_lambda.invoke(aws_commons.create_lambda_function_arn('ARN FUNCAO LAMBDA', 'us-east-1'), '{"body": "Hello Word"}'::json);
```
Agora vá a AWS Console e observe os logs da função lambda no cloud watch. Veja que o resultado apresentado lá dentro condiz com 
o valor que passamos dentro da função.

## Testando funcionalidade de uma maneira mais complexa

Vamos agora fazer algo mais complexo. Utilizaremos um trigger para ser acionado sempre quando houver uma inserção no banco de dados. Em seguida
iremos notificar um lambda que apenas escreverá no cloudWatch o valor que inserimos na função.

### Criando uma tabela

Primeiro vamos criar uma tabela para que no momento que inserirmos os dados o nosso trigger seja notificado

```sql
CREATE TABLE store (
  store_id SERIAL PRIMARY KEY,
  name_store VARCHAR(100) NOT NULL,
  address VARCHAR(100) NOT NULL,    
  segments VARCHAR(100) NOT NULL
);

```
### Criando a estrutura do trigger

Para se criar um trigger é muito simples então podemos seguir o que está descrito na [documentação oficial](https://www.postgresql.org/docs/current/sql-createtrigger.html)


```sql
CREATE TRIGGER integration_lambda_trigger
  AFTER INSERT ON store
  FOR EACH ROW 
  EXECUTE FUNCTION integration_lambda()

-- integration_lambda_trigger: nome do trigger
-- integration_lambda() nome da function

```

Em seguida precisamos criar uma função que será chamada quando o trigger for acionado

```sql
CREATE FUNCTION integration_lambda() RETURNS TRIGGER AS $$
  DECLARE
    json_text TEXT;

  BEGIN 
    json_text := json_build_object('store_id', NEW.store_id, 'name_store', NEW.name_store, 'address', NEW.address, 'segments', NEW.segments);

    PERFORM aws_lambda.invoke(aws_commons.create_lambda_function_arn('arn:aws:lambda:us-east-1:AWS_ACCOUNT_ID:function:change-data-capture','us-east-1'), json_text::json);
    
    return NEW;

  END;
$$ LANGUAGE plpgsql;
```

Iniciamos a função com uma declaração de variável chamada json_text, nós utilizaremos para armazenar 
o valor de retorno da função chamada [json_build_object()](https://www.postgresql.org/docs/current/functions-json.html). Ela será a responsável por criar um JSON de 
acordo com os dados que inserimos na tabela `store`. Para isso, teremos que estruturar a função da 
seguinte maneira. Devemos passar o nome da chave do json e logo em seguida o seu respectivo valor. 
Para pegarmos este valor podemos utilizar o operador `NEW` composto pelo nome da coluna da tabela. `NEW.store_id`


O próximo passo será fazer a chamada para a função Lambda com aws_lambda.invoke. Como primeiro parâmetro 
da função temos que passar o endereço da nossa lambda, ou seja o ARN e a região no qual a lambda foi criada. 
Já no segundo parâmetro, passamos a variável json_text no qual estará armazenado o JSON que enviaremos ao lambda. 
Observe também a expressão ::json. Somos obrigados a passar esse valor porque temos que fazer um cast para deixar explícito o tipo de dado que estamos enviando.

Por fim, retornamos novamente o operador NEW no final da função. 

Se observar no repositório, teremos um script SQL no qual temos todos esses passos sendo executados. Portanto vamos utilizá-lo enviando o comando no momento de fazer a conexão
com o banco de dados. 

Mas também podemos utilizar o PgAdmim para executar todas as funcionalides incluidas no script. 

```sh
psql -h {nome-do-cluster}.{identificador-unico}.{regiao}.rds.amazonaws.com -U cdcStoreDevTo -p 5432 -d cdcstore -f "localizacão do script .SQL"

```
***Lembre-se que a senha para acesso ao banco se encontra no secret manager.***

Se você acabou de criar sua a sua instância e executou o script .sql, certamente você não terá nenhum recurso criado, logo aparecerá no seu terminal alguns logs de erro
como esses 

`.../sql/script.sql:1: ERROR:  relation "store" does not exist`

`.../sql/script.sql:2: ERROR:  could not find a function named "integration_lambda"`

`.../sql/script.sql:3: ERROR:  table "store" does not exist`

`.../sql/script.sql:5: NOTICE:  extension "aws_lambda" already exists, skipping`

Mas não se preocupe, esses erros só ocorrerão quando você executar pela primeira vez, já que a todo o momento que executamos o script, adicionei 
algumas funcionalidades para remover todos os recursos criados anteriormente e recriá-los novamente. 

A seguir podemos executar alguns inserts para visualizar todos os recursos em funcionamento. 

```sql
INSERT INTO store (store_id, name_store, address, segments) VALUES (1, 'my store', '76 street', 'tecnology');

INSERT INTO store (store_id, name_store, address, segments) VALUES (2, 'my store', '76 street', 'tecnology');
```

Se os comando retornarem sucesso após a sua execução, podemos olhar no CloudWatch e verificarmos o que a função lambda 
recebeu

```
2024-12-18T20:01:12.517Z	INFO	{
  store_id: 1,
  name_store: 'my store',
  address: '76 street',
  segments: 'tecnology'
}
```

```
2024-12-18T20:01:19.034Z	INFO	{
  store_id: 2,
  name_store: 'my store',
  address: '76 street',
  segments: 'tecnology'
}
```