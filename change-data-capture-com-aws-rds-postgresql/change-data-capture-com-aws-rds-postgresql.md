# Change data capture com AWS RDS e PostgreSQL

## Introdução

#### Visão geral
Change Data Capture ou CDC é um método utilizado para extrair dados de uma base primária para uma outra base de destino utilizando algum conector viabilizar esta comunicação

![image](https://github.com/user-attachments/assets/036e19c7-a1aa-47fe-85b9-b81b64b8a4cc)

Este conector será ativado quando ocorrer um evento no qual irá alterar o estado da sua base de dados primária.

Após a ocorrência deste evento, o conector será ativado recebendo os dados que foram alterados, com estes dados em mãos nós podemos enviá-los para outro ambiente, como por exemplo uma outra base de dados no qual sua funcionalidade principal é ser um data lake.

Existem diversas ferramentas que poderíamos escolher para desenvolvermos o nosso fluxo de change data capture. O Dynamodb streams e AWS RDS com SQL Server são algumas ferramentas que possuem a funcionalidade de captura de eventos e migração de dados de forma nativa. Mas também podemos criar o nosso próprio change data capture utilizando os triggers do PostgreSQL para capturar as mudanças de estados e enviá-las ao conector. 

Portanto ao decorrer deste artigo, irei mostrar como poderemos criar o nosso próprio fluxo de change data capture utilizando o AWS RDS Aurora PostgreSQL, criaremos os triggers para observarmos as mudanças de estado e utilizaremos a extensão aws_lambda para enviar os dados ao conector AWS lambda.

### Quando utilizar 
### Quando não utilizar 

## Criando um change data capture utilizando um cluster AWS RDS Aurora PostgreSQL

### Criando e configurando o cluster AWS RDS PostgreSQL
### Configurando o IAM

### Instalando a extensão aws_lambda

## Criando a função lambda

### Criação e configuração da função lambda

## Conectando o AWS RDS com a função lambda 

### Criando um trigger
### Testando funcionalidade
