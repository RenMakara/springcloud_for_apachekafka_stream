package co.istad.makara.kafkastream.stream;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Supplier;

import org.apache.avro.generic.GenericRecord;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class StreamConfig {

    // Supplier for producing message into kafka topic
    // Function for processing message and send to destination kafka topic
    // Consumer for consuming message from kafka topic

    @Bean
    public Consumer<GenericRecord> processOracleMessage() {
        return record -> {
            // Dynamic field discovery
            Map<String, Object> data = new LinkedHashMap<>();
            record.getSchema().getFields().forEach(field -> {
                String fieldName = field.name();
                Object fieldValue = record.get(fieldName);
                data.put(fieldName, fieldValue);
                System.out.println(fieldName + ": " + fieldValue);
            });

            System.out.println("Full Record: " + data);
        };
    }

    @Bean
    public Function<Product, Product> processProductDetail(){
        return product -> {

            System.out.println("Old product: " + product.getCode());
            System.out.println("Old product: " + product.getQty());

            // process
            product.setCode("ISTAD-"+product.getCode().toUpperCase());

            // Producing
            return product;
        };
    }

    @Bean
    public Consumer<Product> processProduct() {
        return product -> {
            System.out.println("obj product: " + product.getCode());
            System.out.println("obj product: " + product.getQty());
        };
    }

    // A simple processor: Takes a string, makes it uppercase, and sends it on
    @Bean
    public Consumer<String> processMessage() {
        return input -> {
            System.out.println("Processing: " + input);
        };
    }


}