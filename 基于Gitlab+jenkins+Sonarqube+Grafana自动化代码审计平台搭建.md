## 基于Gitlab+jenkins+Sonarqube+Grafana自动化代码审计平台搭建

##### 背景：针对项目代码质量管理，在目前的微服务/模块化/快迭代的敏捷开发中。如果仅依赖IDE简单检查和人为的代码审查，对于大量代码很不适合。所以对于高效优异的代码，不仅仅依靠开发人员的对于代码编写的规范，同时也需要一些工具来帮助我们提前预防和强制检测代码规范。由此便产生了基于Gitlab+Jenkins+Sonarqube+Grafana的自动化代码审计监控平台。（PS：就是公司有这个需求）

#### 1.项目架构：

![image-20200320135117408](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320135117408.png)

#### 2.环境以及准备:

| 软件或插件名称 | 版本号  |      |
| -------------- | ------- | ---- |
| Gitlab         | v11.0.2 |      |
| Jenkins        | v2.144  |      |
| Sonarqube      | v7.9.2  |      |
| Grafana        | v6.6.2  |      |

针对Gitlab与jenkins通过Webhook进行自动触发构建的相关内容配置我这边不进行叙述了，网上这方面文章很多，我会着重讲后面内容。

#### 3.Jenkins与Sonarqube联动:

##### 3.1首先需要在Sonarqube里面生成一个Sonarqube的令牌，用来给Jenkins使用。在如下地方设置：

![image-20200320143031931](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320143031931.png)

##### 3.2 在jenkins上部署，SonarQube Scanner 扫描插件：

在jenkins中安装插件：SonarQube Scanner for jenkins，如下：

![image-20200320143445564](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320143445564.png)

网页登录jenkins,在Manage Jenkins----Global Tool Conﬁguration----SonarQube Scanner模块中配置 如下设置：

![image-20200320143510707](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320143510707.png)

添加Sonarqube凭证，在凭据-系统中添加全局凭据，类型为Secret text并添加如下token（3.1中的token）。

![image-20200320143538518](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320143538518.png)



然后在Manage Jenkins---conﬁguration模块下面Sonarqube servers中如下添加： 

![image-20200320143607417](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320143607417.png)

然后在job构建中添加如下信息：

```java
sonar.projectKey=demo  (项目名字)
sonar.projectName=demo  (项目名字) 
sonar.language=java sonar.java.binaries=/tmp 
sonar.sources=./ 
sonar.java.source=1.8
sonar.projectVersion=1.0
```

![image-20200320145620799](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320145620799.png)

##### 3.3 效果如下：

###### 3.3.1 提交代码到gitlab：

![image-20200320145843614](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320145843614.png)

###### 3.3.2 gitlab通过webhook自动触发jenkins执行任务

###### 3.3.3 jenkins获取代码，执行sonar分析代码

![image-20200320145921676](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320145921676.png)

###### 3.3.4 在sonar的服务器界面查看分析结果

![image-20200320145955343](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200320145955343.png)

#### 4. Sonarqube与Grafana联动:

首先需要安装influnxdb与Grafana安装环境省略官网均有。

然后写一个Sonarqube数据采集器，具体代码如下：

```python
import requests
import os
import datetime
import time 

from influxdb import InfluxDBClient

BASE_URL = os.getenv('SONAR_BASE_URL', 'http://sonarqube.cn')
USER = os.environ['SONAR_USER']
PASSWORD = os.getenv('SONAR_PASSWORD', '')
INFLUX_URL = os.getenv('INFLUX_URL', '10.100.2.20')
INFLUX_USER = os.environ['INFLUX_USER']
INFLUX_PASSWORD = os.environ['INFLUX_PASSWORD']
INFLUX_DB = os.environ['INFLUX_DB']
INTERVAL = os.environ['INTERVAL']

class SonarApiClient:

    def __init__(self, user, passwd):
        self.user = user
        self.passwd = passwd

    def _make_request(self, endpoint):
        r = requests.get(BASE_URL + endpoint, auth=(self.user, self.passwd))
        return r.json()
    
    def get_all_ids(self, endpoint):
        data = self._make_request(endpoint)
        ids = []
        for component in data['components']:
            dict = {
                'id': component['id'],
                'key': component['key']
            }
            ids.append(dict)
        return ids
    
    def get_all_available_metrics(self, endpoint):
        data = self._make_request(endpoint)
        metrics = []
#        metrics1 = [vulnerabilities]
        for metric in data['metrics']:
            if metric['type'] in ['INT','MILLISEC','WORK_DUR','FLOAT','PERCENT','RATING']:
                metrics.append(metric['key'])
#               metrics = metrics + metrics1
				
        return metrics
    
    def get_measures_by_component_id(self, endpoint):
        data = self._make_request(endpoint)
        return data['component']['measures']


class Project:

    def __init__(self, identifier, key):
        self.id = identifier
        self.key = key
        self.metrics = None
        self.timestamp = datetime.datetime.utcnow().isoformat()

    def set_metrics(self, metrics):
        self.metrics = metrics

    def export_metrics(self):
        influx_client = InfluxDBClient(
            host=INFLUX_URL,
            port=30019,
            username=INFLUX_USER,
            password=INFLUX_PASSWORD,
            database=INFLUX_DB
        )
        influx_client.write_points(self._prepare_metrics())

    def _prepare_metrics(self):
        json_to_export = []
        for metric in self.metrics:
            one_metric = {
                "measurement": metric['metric'],
                "tags": {
                    "id": self.id,
                    "key": self.key
                },
                "time": self.timestamp,
                "fields": {
                    "value": float(metric['value'] if ('value' in metric) else 0)
                }
            }
            json_to_export.append(one_metric)
        return json_to_export

count=0
print ("before while loop...")

while True:
    count += 1
    print ("count -----")
    print (count)

    print ("begin export data...")

    client = SonarApiClient(USER, PASSWORD)
    ids = client.get_all_ids('/api/components/search?qualifiers=TRK')
    
    metrics = client.get_all_available_metrics('/api/metrics/search')
    comma_separated_metrics = ''
    for metric in metrics:
        comma_separated_metrics += metric + ','
    
    uri = '/api/measures/component'
    for item in ids:
        project_id = item['id']
        project_key = item['key']
        print(project_key, project_id)
        project = Project(identifier=project_id, key=project_key)
        component_id_query_param = 'componentId=' + project_id
        metric_key_query_param = 'metricKeys=' + comma_separated_metrics
        measures = client.get_measures_by_component_id(uri + '?' + component_id_query_param + '&' + metric_key_query_param + 'vulnerabilities')
        project.set_metrics(measures)
        project.export_metrics()

    time.sleep(int(INTERVAL))
```

因为我是在dokcer中部署Garafana以及sonarqube等相关程序的，所以建议将首先将sonar_san_docker相关内容制作成镜像。命令如下：

```bash
#build a image for collector
cd sonar_san_docker
docker build -t export-sonarqube:v0.1 .
```

```bash
docker run -d \
--name export-sonarqube \
-e SONAR_USER=admin \
-e SONAR_PASSWORD=password \
-e INFLUX_USER=root \
-e INFLUX_PASSWORD=password \
-e INFLUX_DB=sonarqube_data \
-e INTERVAL=43200  \
export-sonarqube:v0.1
```

至此influnxdb数据库便采集到了数据：

![image-20200323144050053](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200323144050053.png)

然后数据也会传到Grafana中：

![image-20200323144159835](C:\Users\zl\AppData\Roaming\Typora\typora-user-images\image-20200323144159835.png)

