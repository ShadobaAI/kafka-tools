import json
import random
import string
import uuid
from datetime import datetime, timedelta
from time import sleep, time
from kafka import KafkaProducer


class KafkaMessageGenerator:
    def __init__(self, bootstrap_servers='localhost:9092'):
        self.producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode('utf-8'),
            linger_ms=100,
            batch_size=65536,
            buffer_memory=67108864,
            max_in_flight_requests_per_connection=10,
            acks=1
        )
        
        self.russian_chars = 'абвгдежзийклмнопрстуфхцчшщъыьэюяАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯёЁ'
        self.all_chars = string.ascii_letters + self.russian_chars + string.digits + '_'
    
    def random_string(self, length):
        return ''.join(random.choice(self.all_chars) for _ in range(length))
    
    def random_datetime(self, start_year=100, end_year=2100):
        start = datetime(start_year, 1, 1)
        end = datetime(end_year, 12, 31)
        delta = end - start
        random_days = random.randint(0, delta.days)
        random_seconds = random.randint(0, 86400)
        result = start + timedelta(days=random_days, seconds=random_seconds)
        return result.strftime('%Y-%m-%dT%H:%M:%S')
    
    def generate_register_message(self):
        return {
            "event": datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
            "catalog": str(uuid.uuid4()),
            "boolean": random.choice([True, False]),
            "string": self.random_string(random.randint(40, 60)),
            "number": round(random.uniform(1000000, 9999999999), 4),
            "dateTime": self.random_datetime(),
            "uuid": str(uuid.uuid4()),
            "comment": self.random_string(random.randint(60, 80))
        }
    
    def generate_catalog_message(self):
        table_rows = random.randint(1, 3)
        return {
            "ref": str(uuid.uuid4()),
            "isDeleted": random.choice([True, False]),
            "name": self.random_string(random.randint(80, 120)),
            "dateTime": datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
            "number": round(random.uniform(1000000, 9999999999), 4),
            "boolean": random.choice([True, False]),
            "enum": random.choice(["Значение1", "Значение2", "Значение3"]),
            "comment": self.random_string(random.randint(60, 100)),
            "table": [
                {
                    "dateTime": self.random_datetime(),
                    "string": self.random_string(random.randint(50, 65))
                }
                for _ in range(table_rows)
            ]
        }
    
    def send_messages(self, total_messages, messages_per_second, topic=None):
        """
        :param total_messages: Общее количество сообщений
        :param messages_per_second: Скорость (0 = максимальная)
        :param topic: None (оба), 'register', 'catalog'
        """
        interval = 0 if messages_per_second == 0 else 1.0 / messages_per_second
        
        speed_info = "максимальная скорость" if messages_per_second == 0 else f"{messages_per_second} msg/sec"
        topic_info = 'оба топика' if topic is None else topic
        
        print(f"Отправка в {topic_info} ({speed_info})")
        
        report_interval = max(1, total_messages // 100)
        start_time = time()
        
        for i in range(total_messages):
            loop_start = time()
            
            if topic is None or topic == 'register':
                register_msg = self.generate_register_message()
                self.producer.send('1c.test-register', value=register_msg)
            
            if topic is None or topic == 'catalog':
                catalog_msg = self.generate_catalog_message()
                self.producer.send('1c.test-catalog', value=catalog_msg)
            
            if (i + 1) % report_interval == 0 or i == total_messages - 1:
                elapsed = time() - start_time
                current_speed = (i + 1) / elapsed if elapsed > 0 else 0
                progress = ((i + 1) / total_messages) * 100
                print(f"\r[{progress:5.1f}%] {i+1:,}/{total_messages:,} | {current_speed:,.0f} msg/sec", end='', flush=True)
            
            if interval > 0:
                loop_elapsed = time() - loop_start
                sleep_time = max(0, interval - loop_elapsed)
                sleep(sleep_time)
        
        print()
        self.producer.flush()
        total_time = time() - start_time
        msg_count = total_messages * 2 if topic is None else total_messages
        avg_speed = total_messages / total_time if total_time > 0 else 0
        print(f"Завершено! Отправлено {msg_count:,} сообщений | Средняя скорость: {avg_speed:,.0f} msg/sec")
    
    def close(self):
        self.producer.close()


if __name__ == '__main__':
    
    BOOTSTRAP_SERVERS = 'localhost:29091,localhost:29092'
    generator = KafkaMessageGenerator(bootstrap_servers=BOOTSTRAP_SERVERS)

    try:
        
        # catalog, register
        data = [
            {"total": 1_000_000, "speed": 0, "topic": "register"},
            # {"total": 10_000, "speed": 100}, # "topic": "register"},
            # {"total": 1_000, "speed": 10}, # "topic": "register"},
            # {"total": 10_000, "speed": 100}, # "topic": "register"},
            # {"total": 100, "speed": 1}, # "topic": "register"},
            # {"total": 1_000, "speed": 10}, # "topic": "register"},
            # {"total": 30_000, "speed": 1500}, # "topic": "catalog"},
        ]
        
        for wave in data:
            wave_start = datetime.now()
            print(f"\nСтарт волны: {wave_start.strftime('%Y-%m-%d %H:%M:%S')}")
            
            generator.send_messages(
                total_messages=wave["total"],
                messages_per_second=wave["speed"],
                topic=wave.get("topic")
            )
            
            wave_end = datetime.now()
            wave_duration = wave_end - wave_start
            print(f"Финиш волны: {wave_end.strftime('%Y-%m-%d %H:%M:%S')} | Время: {wave_duration}")
        
        sum_total = sum(wave["total"] for wave in data)
        print(f"\nВсего итераций: {sum_total:,}")

    except KeyboardInterrupt:
        print("\nОстановлено пользователем")
    finally:
        generator.close()