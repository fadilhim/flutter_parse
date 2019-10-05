import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../flutter_parse.dart';

import 'parse_exception.dart';
import 'parse_user.dart';

final ParseHTTPClient parseHTTPClient = ParseHTTPClient._internal();

class ParseHTTPClient {
  ParseHTTPClient._internal()
      : this._httpClient =
            parse.configuration.httpClient ?? _ParseBaseHTTPClient();

  final http.BaseClient _httpClient;

  String _getFullUrl(String path) {
    return parse.configuration.uri.origin + path;
  }

  Future<Map<String, String>> _addHeader(
      Map<String, String> additionalHeaders) async {
    assert(parse.applicationId != null);
    final headers = additionalHeaders ?? <String, String>{};

    headers["User-Agent"] = "Dart Parse SDK v${kParseSdkVersion}";
    headers['X-Parse-Application-Id'] = parse.applicationId;

    // client key can be null with self-hosted Parse Server
    if (parse.clientKey != null) {
      headers['X-Parse-Client-Key'] = parse.clientKey;
    }

    headers['X-Parse-Client-Version'] = "dart${kParseSdkVersion}";

    final currentUser = await ParseUser.currentUser;
    if (currentUser != null && currentUser.sessionId != null) {
      headers['X-Parse-Session-Token'] = currentUser.sessionId;
    }

    return headers;
  }

  Future<dynamic> _parseResponse(http.Response httpResponse,
      {bool ignoreResult = false}) {
    String response = httpResponse.body;
    final result = json.decode(response);

    if (parse.enableLogging) {
      print("╭-- JSON");
      _parseLogWrapped(response);
      print("╰-- result");
    }

    if (ignoreResult) {
      return null;
    }

    if (result is Map<String, dynamic>) {
      String error = result['error'];
      if (error != null) {
        int code = result['code'];
        throw ParseException(code: code, message: error);
      }

      return Future.value(result);
    } else if (result is List<dynamic>) {
      return Future.value(result);
    }

    throw ParseException(
        code: ParseException.invalidJson, message: 'invalid server response');
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic> params,
    Map<String, String> headers,
  }) async {
    headers = await _addHeader(headers);
    final url = _getFullUrl(path);

    if (params != null) {
      final uri = Uri.parse(url).replace(queryParameters: params);
      return _httpClient
          .get(uri, headers: headers)
          .then((r) => _parseResponse(r));
    }

    return _httpClient
        .get(url, headers: headers)
        .then((r) => _parseResponse(r));
  }

  Future<dynamic> delete(
    String path, {
    Map<String, String> params,
    Map<String, String> headers,
  }) async {
    headers = await _addHeader(headers);
    final url = _getFullUrl(path);

    if (params != null) {
      var uri = Uri.parse(url).replace(queryParameters: params);
      return _httpClient.delete(uri, headers: headers).then((r) {
        return _parseResponse(r);
      });
    }

    return _httpClient
        .delete(url, headers: headers)
        .then((r) => _parseResponse(r));
  }

  Future<dynamic> post(
    String path, {
    Map<String, String> headers,
    dynamic body,
    Encoding encoding,
    bool ignoreResult = false,
  }) async {
    headers = await _addHeader(headers);
    final url = _getFullUrl(path);

    return _httpClient
        .post(url, headers: headers, body: body, encoding: encoding)
        .then((r) => _parseResponse(r, ignoreResult: ignoreResult));
  }

  Future<dynamic> put(
    String path, {
    Map<String, String> headers,
    dynamic body,
    Encoding encoding,
  }) async {
    headers = await _addHeader(headers);
    final url = _getFullUrl(path);

    return _httpClient
        .put(url, headers: headers, body: body, encoding: encoding)
        .then((r) => _parseResponse(r));
  }
}

class _ParseBaseHTTPClient extends http.BaseClient {
  final http.Client _client;

  _ParseBaseHTTPClient() : this._client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (parse.enableLogging) {
      logToCURL(request);
    }

    return await _client.send(request);
  }
}

void logToCURL(http.BaseRequest request) {
  var curlCmd = "curl -X ${request.method} \\\n";
  var compressed = false;
  var bodyAsText = false;
  request.headers.forEach((name, value) {
    if (name.toLowerCase() == "accept-encoding" &&
        value.toLowerCase() == "gzip") {
      compressed = true;
    } else if (name.toLowerCase() == "content-type") {
      bodyAsText =
          value.contains('application/json') || value.contains('text/plain');
    }
    curlCmd += ' -H "$name: $value" \\\n';
  });
  if (<String>['POST', 'PUT', 'PATCH'].contains(request.method)) {
    if (request is http.Request) {
      curlCmd +=
          " -d '${bodyAsText ? request.body : request.bodyBytes}' \\\n  ";
    }
  }
  curlCmd += (compressed ? " --compressed " : " ") + request.url.toString();
  print("╭-- cURL");
  _parseLogWrapped(curlCmd);
  print("╰-- (copy and paste the above line to a terminal)");
}

void _parseLogWrapped(String text) {
  final pattern = RegExp('.{1,800}'); // 800 is the size of each chunk
  pattern.allMatches(text).forEach((match) => print(match.group(0)));
}
