package com.github.catvod.net;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import okhttp3.Call;
import okhttp3.FormBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

public class OkHttp {

    private static volatile OkHttpClient shared;

    public static OkHttpClient client() {
        OkHttpClient client = shared;
        if (client == null) {
            synchronized (OkHttp.class) {
                client = shared;
                if (client == null) {
                    client = new OkHttpClient.Builder()
                            .connectTimeout(15, TimeUnit.SECONDS)
                            .readTimeout(30, TimeUnit.SECONDS)
                            .writeTimeout(30, TimeUnit.SECONDS)
                            .followRedirects(true)
                            .followSslRedirects(true)
                            .build();
                    shared = client;
                }
            }
        }
        return client;
    }

    public static OkHttpClient client(long timeoutMillis) {
        return client().newBuilder()
                .connectTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                .readTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                .build();
    }

    public static Request.Builder builder(String url, Map<String, String> headers) {
        Request.Builder builder = new Request.Builder().url(url);
        if (headers != null) {
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                if (entry.getKey() != null && entry.getValue() != null) {
                    builder.header(entry.getKey(), entry.getValue());
                }
            }
        }
        return builder;
    }

    public static Call newCall(String url, Map<String, String> headers) {
        return client().newCall(builder(url, headers).build());
    }

    public static String get(String url) throws IOException {
        return get(url, null);
    }

    public static String get(String url, Map<String, String> headers) throws IOException {
        try (Response response = newCall(url, headers).execute()) {
            return bodyText(response);
        }
    }

    public static String post(String url, Map<String, String> params) throws IOException {
        return post(url, params, null);
    }

    public static String post(String url, Map<String, String> params, Map<String, String> headers) throws IOException {
        FormBody.Builder form = new FormBody.Builder();
        if (params != null) {
            for (Map.Entry<String, String> entry : params.entrySet()) {
                if (entry.getKey() != null && entry.getValue() != null) {
                    form.add(entry.getKey(), entry.getValue());
                }
            }
        }
        Request request = builder(url, headers).post(form.build()).build();
        try (Response response = client().newCall(request).execute()) {
            return bodyText(response);
        }
    }

    public static String post(String url, String body, Map<String, String> headers, String contentType) throws IOException {
        okhttp3.MediaType mediaType = contentType == null ? null : okhttp3.MediaType.parse(contentType);
        Request request = builder(url, headers)
                .post(okhttp3.RequestBody.create(body == null ? "" : body, mediaType))
                .build();
        try (Response response = client().newCall(request).execute()) {
            return bodyText(response);
        }
    }

    private static String bodyText(Response response) throws IOException {
        ResponseBody body = response.body();
        return body == null ? "" : body.string();
    }
}
