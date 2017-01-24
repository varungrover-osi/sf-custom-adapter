global class DataSourceConnectionForMongo extends DataSource.Connection {

    //Constructor
    global DataSourceConnectionForMongo(DataSource.ConnectionParams connectionParams) {

    }
    
    //Method to Sync the metadata
    //This is a sample schema, change your schema according to your external data tables/entities.
    override global List<DataSource.Table> sync() {
        List<DataSource.Table> tables = new List<DataSource.Table>();
        List<DataSource.Column> columns;
        columns = new List<DataSource.Column>();
        columns.add(DataSource.Column.text('Points', 255));
        columns.add(DataSource.Column.text('Name', 255));
        columns.add(DataSource.Column.text('NickName', 255));
        columns.add(DataSource.Column.text('Location', 255));
        columns.add(DataSource.Column.text('PredictedMatchScore', 255));
        columns.add(DataSource.Column.text('PredictedBatsmanScore', 255));
        columns.add(DataSource.Column.text('Team', 255));
        columns.add(DataSource.Column.text('ManOfTheMatch', 255));
        columns.add(DataSource.Column.text('Batsman', 255));
        columns.add(DataSource.Column.text('Bowler', 255));
        columns.add(DataSource.Column.text('Match', 255));
        columns.add(DataSource.Column.text('Points', 255));
        columns.add(DataSource.Column.text('ExternalId', 255));
        columns.add(DataSource.Column.url('DisplayUrl'));
        tables.add(DataSource.Table.get('MatchBidTable', 'Title',
            columns));
        return tables;
    }
    
    

    /**************************************
    The following methods are called by salesforce internally based on the CRUD operation selected by the user/API
    ***************************************/

    //Method that will be called when querying data
    override global DataSource.TableResult query(DataSource.QueryContext context) {
        if (context.tableSelection.columnsSelected.size() == 1 &&
            context.tableSelection.columnsSelected.get(0).aggregation ==
            DataSource.QueryAggregation.COUNT) {
            List<Map<String,Object>> rows = getRows();
            List<Map<String,Object>> response = DataSource.QueryUtils.filter(context, getRows());
            List<Map<String, Object>> countResponse = new List<Map<String, Object>>();
            Map<String, Object> countRow = new Map<String, Object>();
            countRow.put(context.tableSelection.columnsSelected.get(0).columnName,response.size());
            countResponse.add(countRow);
            return DataSource.TableResult.get(context,countResponse);
            } else {
                List<Map<String,Object>> filteredRows = DataSource.QueryUtils.filter(context, getRows());
                System.debug('filteredRows - ' + filteredRows.size());
                List<Map<String,Object>> sortedRows = DataSource.QueryUtils.sort(context, filteredRows);
                System.debug('sortedRows - ' + sortedRows.size());
                List<Map<String,Object>> limitedRows = DataSource.QueryUtils.applyLimitAndOffset(context, sortedRows);
                System.debug('limitedRows - ' + limitedRows.size());
                return DataSource.TableResult.get(context, limitedRows);
            }
        }


    //Method that will be called on global search
    override global List<DataSource.TableResult> search(DataSource.SearchContext context) {
        List<DataSource.TableResult> results = new List<DataSource.TableResult>();
        for (DataSource.TableSelection tableSelection : context.tableSelections) {
            results.add(DataSource.TableResult.get(tableSelection, getRows()));
        }
        return results;
    }
    

    //Method that will be called when delete is called
    global override List<DataSource.DeleteResult> deleteRows(DataSource.DeleteContext context) {
     if (context.tableSelected == 'MatchBidTable'){
         List<DataSource.DeleteResult> results = new List<DataSource.DeleteResult>();
         for (String externalId : context.externalIds){
          HttpResponse response = makeDeleteCallout(externalId);
          if (response.getStatusCode() == 200){
           results.add(DataSource.DeleteResult.success(externalId));
       }
       else {
           results.add(DataSource.DeleteResult.failure(externalId,'Callout delete error:'+ response.getBody()));
       }
   }
   return results;
}
return null;
}


     //Method that will be called on update or insert
     global override List<DataSource.UpsertResult> upsertRows(DataSource.UpsertContext context) {
        if (context.tableSelected == 'MatchBidTable') {
             List<DataSource.UpsertResult> results = new List<DataSource.UpsertResult>();

             List<Map<String, Object>> rows = context.rows;

             for (Map<String, Object> row : rows){
              // Make a callout to insert or update records in the external system.
              HttpResponse response;
              // Determine whether to insert or update a record.
              if (row.get('ExternalId') == null){
                 // Send a POST HTTP request to insert new external record.
                 // Make an Apex callout and get HttpResponse.
                 String jsonBody = '{"batsman": { "name": "' + row.get('Batsman') + '"' + '}}';
                 System.debug('Json - ' + jsonBody);
                 response = makePostCallout(jsonBody);
             }
             else {
                 // Send a PUT HTTP request to update an existing external record.
                 // Make an Apex callout and get HttpResponse.
                 response = makePutCallout('{"batsman": { "name": "' + row.get('Batsman') + '"' + '}}', String.valueOf(row.get('ExternalId')));
             }

              // Check the returned response.
              // First, deserialize it.
              Map<String, Object> m = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
              if (response.getStatusCode() == 200){
                Map<String, Object> idMap = (Map<String,Object>)m.get('_id');
                  results.add(DataSource.UpsertResult.success(String.valueOf(idMap.get('$oid'))));
              }
              else {
               results.add(DataSource.UpsertResult.failure(String.valueOf(m.get('_id')),'The callout resulted in an error: ' +response.getStatusCode()));
           }
       }
       return results;
   }
   return null;
}


    /**************************************
    Helper Methods
    ***************************************/


    // Helper method to get record values from the external system for the Sample table.
    private List<Map<String, Object>> getRows () {
        // Get row field values for the Sample table from the external system via a callout.
        HttpResponse response = makeGetCallout();
        // Parse the JSON response and populate the rows.
        List<Object> m = (List<Object>)JSON.deserializeUntyped(response.getBody());
        System.debug('m - ' + m);
        
        //Map<String, Object> error = (Map<String, Object>)m.get('error');
        //if (error != null) {
            //throwException(string.valueOf(error.get('message')));
        //}
        
        List<Map<String,Object>> rows = new List<Map<String,Object>>();
        List<Object> jsonRows = m;
        
        for (Object jsonRow : jsonRows) {
            Map<String,Object> row = (Map<String,Object>)jsonRow;
            rows.add(foundRow(row));
        }
        
        System.debug('Total Rows - ' + rows.size());

        return rows;
    }

    // Populate a row based on values from the external system.
    private Map<String,Object> foundRow(Map<String,Object> foundRow) {
        Map<String,Object> row = new Map<String,Object>();
        Map<String,Object> externalIdMap = (Map<String,Object>)foundRow.get('_id');
        Map<String,Object> teamMemberMap = (Map<String,Object>)foundRow.get('teamMember');
        Map<String,Object> teamMap = (Map<String,Object>)foundRow.get('team');
        Map<String,Object> momMap = (Map<String,Object>)foundRow.get('mom');
        Map<String,Object> matchMap = (Map<String,Object>)foundRow.get('match');
        Map<String,Object> bowlerMap = (Map<String,Object>)foundRow.get('bowler');
        Map<String,Object> batsmanMap = (Map<String,Object>)foundRow.get('batsman');
        
        if(teamMemberMap == null || teamMap == null || momMap == null || matchMap == null || bowlerMap == null || batsmanMap == null)
        {
            System.debug('ID FOUND' + externalIdMap.get('$oid'));
        }

        row.put('ExternalId', externalIdMap.get('$oid'));
        row.put('DisplayUrl', string.valueOf('Display URL'));
        row.put('Points', string.valueOf(foundRow.get('points')));
        row.put('Location', teamMemberMap.get('location') == null ? '' : teamMemberMap.get('location'));
        row.put('Name', teamMemberMap.get('name'));
        row.put('NickName', teamMemberMap.get('nickName'));
        row.put('Batsman', batsmanMap.get('name'));
        row.put('Bowler', bowlerMap.get('name'));
        row.put('ManOfTheMatch', momMap.get('name'));
        row.put('Match', matchMap.get('name'));
        row.put('PredictedBatsmanScore', foundRow.get('predictedBatsmanScore'));
        row.put('PredictedMatchScore', foundRow.get('predictedMatchScore'));
        row.put('Team', teamMap.get('name'));
        return row;

    }
    

    /**************************************
    The following methods are called Methods which Use Rest Service to get the data from external systems.
    ***************************************/

    //Make a GET Callout
    private HttpResponse makeGetCallout() {
        HttpRequest req = new HttpRequest();
        
        //Set HTTPRequest method
        req.setMethod('GET');
        //req.setHeader('application-id', 'xxxxxxxxxxxxxxxxxxxxx');
    //req.setHeader('secret-key','xxxxxxxxxxxxxxxxxxxxx');
    //req.setHeader('application-type','REST');
    req.setEndpoint('https://api.mlab.com/api/1/databases/cricket/collections/MatchPointsPOC?l=1000&apiKey=yourmongolabkey');

    Http http = new Http();
    //Execute web service call here      
    HTTPResponse res = http.send(req); 
    try {

          //Helpful debug messages
          System.debug(res.toString());
          System.debug('STATUS:'+res.getStatus());
          System.debug('STATUS_CODE:'+res.getStatusCode());
          System.debug('Response:' + res.getBody());
          } catch(System.CalloutException e) {
                //Exception handling goes here....
                System.debug('Error in getting records');
            }     

            return res;
        }

     //Make a POST callout
     private static HttpResponse makePostCallout(String jsonBody) {
       HttpRequest req = new HttpRequest();

        //Set HTTPRequest method
        req.setMethod('POST');
        req.setHeader('application-type','REST');
        req.setHeader('Content-Type','application/json');
        req.setEndpoint('https://api.mlab.com/api/1/databases/cricket/collections/MatchPointsPOC?apiKey=yourmongolabkey');
        req.setBody(jsonBody);

        Http http = new Http();
    //Execute web service call here      
    HTTPResponse res = http.send(req);

    try {

          //Helpful debug messages
          System.debug(res.toString());
          System.debug('STATUS:'+res.getStatus());
          System.debug('STATUS_CODE:'+res.getStatusCode());
          System.debug('Response:' + res.getBody());
          } catch(System.CalloutException e) {
                //Exception handling goes here....
                System.debug('Error in getting records');
            }     

            return res;
        }

     // Make a PUT callout
     private static HttpResponse makePutCallout(String jsonBody, String externalID) {
       HttpRequest req = new HttpRequest();

        //Set HTTPRequest method
        req.setMethod('PUT');
        req.setHeader('Content-Type','application/json');
        req.setEndpoint('https://api.mlab.com/api/1/databases/cricket/collections/MatchPointsPOC/' + externalId + '?apiKey=yourmongolabkey');
        req.setBody(jsonBody);

        Http http = new Http();
    //Execute web service call here      
    HTTPResponse res = http.send(req);

    try {

          //Helpful debug messages
          System.debug(res.toString());
          System.debug('STATUS:'+res.getStatus());
          System.debug('STATUS_CODE:'+res.getStatusCode());
          System.debug('Response:' + res.getBody());
          } catch(System.CalloutException e) {
                //Exception handling goes here....
                System.debug('Error in getting records');
            }     

            return res;
        }

     // Make a DELETE callout
     private static HttpResponse makeDeleteCallout(String externalID) {
       HttpRequest req = new HttpRequest();

        //Set HTTPRequest method
        req.setMethod('DELETE');
        req.setHeader('application-type','REST');
        req.setEndpoint('https://api.mlab.com/api/1/databases/cricket/collections/MatchPointsPOC/' + externalId + '?apiKey=yourmongolabkey');
        
        Http http = new Http();
    //Execute web service call here      
    HTTPResponse res = http.send(req); 
    try {

          //Helpful debug messages
          System.debug(res.toString());
          System.debug('STATUS:'+res.getStatus());
          System.debug('STATUS_CODE:'+res.getStatusCode());
          System.debug('Response:' + res.getBody());
          } catch(System.CalloutException e) {
                //Exception handling goes here....
                System.debug('Error in getting records');
            }     

            return res;
        }




    }
